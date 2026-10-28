#!/usr/bin/env bash
# 0003: the stack's environment, INFRA_ENV in .env, picks the host name and the upstreams of an
# application's site at registration (RQ-07, AC-07): with INFRA_ENV=demo on the workstation, Faito
# registers from its one routes file with the demo host's names and upstreams, served by the
# running dev Caddy (its dev certificate, no HSTS: register-app.sh only reloads it), in front of echo
# stand-ins named as the demo containers; set back to dev, the dev ones.
#
#   bash tests/0003-env-switch.sh
#
# Never runs up.sh nor docker compose up: Caddy keeps the rules it was started with. .env and
# Faito's site are put back as they were by a trap, whatever happens.
#
# covers: up.sh env.sh compose.yml compose.dev.yml caddy/ keycloak/ keycloak-import/ reverse-proxy/
# covers: certs/ register-app.sh registry.sh registry.txt routes.sh networks.sh
# covers: registration-account.sh tlds-alpha-by-domain.txt examples/routes/
# covers: tests/fixtures/stand-in-upstream/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

CADDY_IMAGE=caddy:2.11.4-alpine
STAND_IN=c4-infra-test-switch
SITE=caddy/apps/faito.caddy

host_path() {
  if command -v cygpath > /dev/null; then cygpath -w "$1"; else printf '%s' "$1"; fi
}

work=$(mktemp -d)
cp .env "$work/env"
[ ! -f "$SITE" ] || cp "$SITE" "$work/faito.caddy"
cleanup() {
  cp "$work/env" .env
  if [ -f "$work/faito.caddy" ]; then cp "$work/faito.caddy" "$SITE"; else rm -f "$SITE"; fi
  MSYS_NO_PATHCONV=1 docker exec c4-infra.reverse-proxy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile > /dev/null 2>&1
  bash register-app.sh --index-only
  docker rm -f $(docker ps -aq -f "name=^$STAND_IN-") > /dev/null 2>&1
  rm -rf "$work"
}
trap cleanup EXIT

set_env() { # <dev|demo>: INFRA_ENV in .env
  sed -i "s/^INFRA_ENV=.*/INFRA_ENV=$1/" .env
  grep -qx "INFRA_ENV=$1" .env
}

# The demo containers' names, as aliases on the c4-infra network
docker rm -f $(docker ps -aq -f "name=^$STAND_IN-") > /dev/null 2>&1
for stand_in in faito.gateway:7080 faito.frontend:80; do
  MSYS_NO_PATHCONV=1 docker run -d --name "$STAND_IN-${stand_in%%.*}-${stand_in#*:}" --network c4-infra \
    --network-alias "${stand_in%:*}" -e PORT="${stand_in#*:}" -e STAND_IN_NAME="${stand_in%:*}" \
    -v "$(host_path "$PWD/tests/fixtures/stand-in-upstream"):/stand-in:ro" \
    "$CADDY_IMAGE" caddy run --config /stand-in/http.caddy --adapter caddyfile > /dev/null
done

# Requests https://<host><path> through the running proxy (-k: the dev certificate doesn't cover the
# demo host names); sets $work/answer, $work/headers and $work/body
fetch() { # <host> <path>
  curl --ssl-no-revoke -sk --resolve "$1:443:127.0.0.1" -D "$work/headers.raw" -o "$work/body" \
    -w '%{http_code} %{redirect_url}' "https://$1$2" > "$work/answer"
  tr -d '\r' < "$work/headers.raw" > "$work/headers"
}

served_by() { # <stand-in> <host> <uri>
  local expected="upstream=$1 host=$2 uri=$3"
  [ "$(cat "$work/body")" = "$expected" ] || { echo "answer: $(cat "$work/answer"), body: $(head -c 300 "$work/body")"; return 1; }
}

answered() { # <status> [<redirect URL>]
  [ "$(cat "$work/answer")" = "$1 ${2:-}" ] || { echo "answer: $(cat "$work/answer")"; return 1; }
}

no_header() { # <name>
  ! grep -qi -- "^$1:" "$work/headers" || { echo "headers:"; cat "$work/headers"; return 1; }
}

site_holds() { # <line, without its indentation>
  sed 's/^[[:space:]]*//' "$SITE" | grep -qxF -- "$1" || { echo "$SITE:"; cat "$SITE"; return 1; }
}

site_lacks() { # <text>
  ! grep -qF -- "$1" "$SITE" || { echo "$SITE holds:"; grep -nF -- "$1" "$SITE"; return 1; }
}

started_at() { docker inspect -f '{{.State.StartedAt}}' c4-infra.reverse-proxy; }
proxy_started=$(started_at)

# INFRA_ENV=demo
check "INFRA_ENV=demo in .env" set_env demo
check "faito registers (INFRA_ENV=demo)" bash register-app.sh --app faito --proxy examples/routes/faito.routes
check "the site says INFRA_ENV=demo" grep -qF '(INFRA_ENV=demo)' "$SITE"
check "the site names faito.c4-soft.com" site_holds 'faito.c4-soft.com {'
check "the site names http://faito.gateway:7080" site_holds 'reverse_proxy http://faito.gateway:7080'
check "the site names http://faito.frontend:80" site_holds 'reverse_proxy http://faito.frontend:80'
check "the site names no dev upstream" site_lacks host.docker.internal
fetch faito.c4-soft.com /gateway/x
check "faito.c4-soft.com/gateway/x: answered by faito.gateway" served_by faito.gateway faito.c4-soft.com /gateway/x
fetch faito.c4-soft.com /fr/x
check "faito.c4-soft.com/fr/x: answered by faito.frontend" served_by faito.frontend faito.c4-soft.com /fr/x
fetch faito.c4-soft.com /en/x
check "faito.c4-soft.com/en/x: answered by faito.frontend" served_by faito.frontend faito.c4-soft.com /en/x
check "the dev Caddy kept its rules: no HSTS" no_header Strict-Transport-Security
fetch faito.dev.localhost /
check "faito.dev.localhost is no longer served" test "$(cat "$work/answer")" != '302 https://faito.dev.localhost/fr/'

# back to INFRA_ENV=dev
check "INFRA_ENV=dev in .env" set_env dev
check "faito registers (INFRA_ENV=dev)" bash register-app.sh --app faito --proxy examples/routes/faito.routes
check "the site says INFRA_ENV=dev" grep -qF '(INFRA_ENV=dev)' "$SITE"
check "the site names faito.dev.localhost again" site_holds 'faito.dev.localhost {'
check "the site names https://host.docker.internal:14080 again" site_holds 'reverse_proxy https://host.docker.internal:14080 {'
check "the site names no demo upstream" site_lacks faito.gateway
fetch faito.dev.localhost /
check "faito.dev.localhost/ is served again (302 to /fr/)" answered 302 https://faito.dev.localhost/fr/
check "Caddy was neither restarted nor recreated" test "$(started_at)" = "$proxy_started"
finish
