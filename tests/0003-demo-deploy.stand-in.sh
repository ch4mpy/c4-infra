#!/usr/bin/env bash
# 0003: the demo deployment on a stand-in demo host (RQ-06, AC-08, AC-09): a host holding only what
# the deployment sends (demo/deploy-files.txt) and the .env demo/write-env.sh writes, mode 600; the
# host's side of the deployment (demo/deploy.sh) starts the stack healthy from the compose base and
# its demo override; then the applications register there: Faito, Hurura'a and Turu from their routes
# files, Turu with its MCP origin (turu-mcp.c4-soft.com, intent 0013).
#
#   bash tests/0003-demo-deploy.stand-in.sh      (bash tests/run.sh --all runs it)
#
# The workflow's `docker compose pull` is skipped: the Keycloak image is the one up.sh builds here,
# loaded into the stand-in, and in no registry; `docker compose up` pulls the others itself. Let's
# Encrypt is kept out (tests/stand-in-host/compose.no-acme.yml).
#
# covers: demo/ compose.yml compose.demo.yml register-app.sh registry.sh registry.txt routes.sh
# covers: networks.sh registration-account.sh tlds-alpha-by-domain.txt caddy/ keycloak/
# covers: keycloak-import/ reverse-proxy/ examples/routes/ tests/fixtures/0003/ tests/stand-in-host/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/stand-in-host.sh

DIR=/root/c4-infra
APPS=/root/apps
FAITO_REALM=${FAITO_DIR:-../faito}/keycloak/import/faito-realm.json

work=$(mktemp -d)
trap 'stand_in_down; rm -rf "$work"' EXIT

in_stack() { # <command…>: in the stack's directory on the stand-in, stdin closed
  stand_in_exec bash -c 'cd "$1" && shift && "$@" < /dev/null' sh "$DIR" "$@"
}

check "the stand-in host starts" stand_in_up
check "the Keycloak and proxy images built here are loaded into it" stand_in_load_image c4-infra/keycloak c4-infra/reverse-proxy
stand_in_exec rm -rf "$DIR" "$APPS"
check "the deployment's files are sent (demo/deploy-files.txt)" stand_in_send "$DIR"
check ".env is written there by demo/write-env.sh" stand_in_env "$DIR"

# exactly what the deployment sends, and .env (plus the test's compose.no-acme.yml)
expected=$(printf '%s\n' $(cat demo/deploy-files.txt) .env compose.no-acme.yml | sort)
holds_only_sent() {
  local found
  found=$(stand_in_exec sh -c 'cd "$1" && find . -type f | sed "s|^\./||" | sort' sh "$DIR" | tr -d '\r')
  [ "$found" = "$expected" ] || { echo "found:"; echo "$found"; return 1; }
}
check "$DIR holds only what the deployment sends" holds_only_sent
mode=$(stand_in_exec stat -c %a "$DIR/.env" | tr -d '\r')
check ".env is mode 600 (it is $mode)" test "$mode" = 600
check ".env says INFRA_ENV=demo" stand_in_exec grep -qx INFRA_ENV=demo "$DIR/.env"
check ".env names the compose base, its demo override and the applications' networks (0007)" \
  stand_in_exec grep -qx 'COMPOSE_FILE=compose.yml:compose.demo.yml:compose.apps.yml:compose.no-acme.yml' "$DIR/.env"

# AC-08: the host's side of the deployment
in_stack bash ./demo/deploy.sh > "$work/deploy.log" 2>&1
status=$?
deployed() { [ "$status" -eq 0 ] || { tail -n 30 "$work/deploy.log"; return 1; }; }
check "bash demo/deploy.sh exits 0" deployed
in_stack docker compose ps --format '{{.Name}} {{.Health}}' | tr -d '\r' > "$work/ps"
all_healthy() {
  [ "$(wc -l < "$work/ps")" -eq 6 ] && ! grep -v ' healthy$' "$work/ps" || { cat "$work/ps"; return 1; }
}
check "every service of the stack is healthy (6)" all_healthy
proxy_env=$(in_stack docker compose exec -T reverse-proxy printenv INFRA_ENV | tr -d '\r')
check "the proxy runs the demo rules (its INFRA_ENV: $proxy_env)" test "$proxy_env" = demo
check "the nightly backup is in the crontab" \
  stand_in_exec sh -c 'crontab -l | grep -qxF "15 3 * * * cd ~/c4-infra && bash ./demo/backup.sh >> ~/backups/c4-infra-backup.log 2>&1"'

# AC-09: the applications register there, from their routes files
stand_in_exec mkdir -p "$APPS"
if [ -f "$FAITO_REALM" ]; then
  stand_in_exec -i sh -c 'cat > "$1"' sh "$APPS/faito-realm.json" < "$FAITO_REALM"
else
  echo "# $FAITO_REALM missing: a minimal realm faito instead"
  printf '{"realm":"faito","enabled":true}\n' | stand_in_exec -i sh -c 'cat > "$1"' sh "$APPS/faito-realm.json"
fi
for app in faito hururaa turu; do
  stand_in_exec -i sh -c 'cat > "$1"' sh "$APPS/$app.routes" < "examples/routes/$app.routes"
done

register() { # <log> <register-app.sh option…>: sets status
  local log=$1
  shift
  RABBITMQ_PASSWORD=$(openssl rand -hex 16) MSYS_NO_PATHCONV=1 docker exec -e RABBITMQ_PASSWORD "$STAND_IN_NAME" \
    bash -c 'cd "$1" && shift && bash ./register-app.sh "$@" < /dev/null' sh "$DIR" "$@" > "$work/$log" 2>&1
  status=$?
}
registered() { # <log>
  [ "$status" -eq 0 ] || { tail -n 20 "$work/$1"; return 1; }
}
refused() { # <log>
  [ "$status" -ne 0 ] || { echo "exited 0:"; tail -n 20 "$work/$1"; return 1; }
}
says() { # <log> <text>
  grep -qF -- "$2" "$work/$1" || { echo "output:"; tail -n 20 "$work/$1"; return 1; }
}
site_names() { # <app> <line>
  stand_in_exec grep -qxF -- "$2" "$DIR/caddy/apps/$1.caddy" || { stand_in_exec cat "$DIR/caddy/apps/$1.caddy"; return 1; }
}

register faito.log --app faito --realm "$APPS/faito-realm.json" --proxy "$APPS/faito.routes" \
  --rabbitmq-user faito-api --rabbitmq-password-env RABBITMQ_PASSWORD
check "Faito registers (realm, RabbitMQ user, routes file)" registered faito.log
check "Faito's site names faito.c4-soft.com" site_names faito 'faito.c4-soft.com {'
check "Faito's site reaches http://faito.gateway:7080" site_names faito $'\t\t\treverse_proxy http://faito.gateway:7080'
check "Caddy serves faito.c4-soft.com (HTTP to HTTPS)" \
  stand_in_exec sh -c 'curl -s -o /dev/null -w "%{http_code} %{redirect_url}" -H "Host: faito.c4-soft.com" http://127.0.0.1/fr/ | grep -qx "308 https://faito.c4-soft.com/fr/"'
register hururaa.log --app hururaa --proxy "$APPS/hururaa.routes"
check "Hurura'a registers from its routes file" registered hururaa.log
check "Hurura'a's site names hururaa.c4-soft.com" site_names hururaa 'hururaa.c4-soft.com {'
register turu.log --app turu --proxy "$APPS/turu.routes"
check "0013: Turu registers, its MCP server's role included" registered turu.log
check "0013: Turu's site names turu.c4-soft.com" site_names turu 'turu.c4-soft.com {'
check "0013: and its MCP origin, turu-mcp.c4-soft.com" site_names turu 'turu-mcp.c4-soft.com {'
check "0013: which reaches http://turu.mcp:9080" site_names turu $'\t\t\treverse_proxy http://turu.mcp:9080'
check "0013: Caddy serves turu-mcp.c4-soft.com (HTTP to HTTPS)" \
  stand_in_exec sh -c 'curl -s -o /dev/null -w "%{http_code} %{redirect_url}" -H "Host: turu-mcp.c4-soft.com" http://127.0.0.1/mcp | grep -qx "308 https://turu-mcp.c4-soft.com/mcp"'
finish
