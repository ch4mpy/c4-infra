#!/usr/bin/env bash
# 0003: the demo host's edge, from the one shared configuration (RQ-01, RQ-02): a throwaway Caddy
# running caddy/ with INFRA_ENV=demo (wrapped with local_certs, no Let's Encrypt) in front of echo
# stand-ins of the shared services, and of Mailpit itself with the demo's MP_UI_AUTH (since 0007,
# Mailpit asks for its credentials, not Caddy). /mailpit/ asks for them and RabbitMQ has no route
# (AC-03), HSTS is sent, and the realm discovery reaches Keycloak rewritten (AC-06). Since intent 0013,
# Turu's MCP origin (turu-mcp.c4-soft.com) reaches an echo stand-in of its MCP server (turu.mcp:9080)
# with X-Forwarded-Host and -Proto, without the single-page-app headers.
#
#   bash tests/0003-demo-edge.sh
#
# covers: caddy/ reverse-proxy/ routes.sh registry.sh registry.txt examples/routes/ rabbitmq/
# covers: tests/fixtures/0013/ tests/fixtures/stand-in-upstream/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

# the reverse proxy's image (compose.yml)
CADDY_IMAGE=caddy:2.11.4-alpine
# the stack's proxy, built by up.sh: Caddy with the rate-limit module the Caddyfile uses (intent 0013)
PROXY_IMAGE=c4-infra/reverse-proxy
NAME=c4-infra-test-edge
HOST=infra.c4-soft.com
PORT=48443

host_path() {
  if command -v cygpath > /dev/null; then cygpath -w "$1"; else printf '%s' "$1"; fi
}

work=$(mktemp -d)
cleanup() {
  docker rm -f $(docker ps -aq -f "name=^$NAME-") > /dev/null 2>&1
  docker network rm "$NAME" > /dev/null 2>&1
  rm -rf "$work"
}
trap cleanup EXIT
cleanup
mkdir -p "$work/apps" "$work/test"

# the demo's Mailpit credentials: a random password, its bcrypt hash in Mailpit's MP_UI_AUTH, as
# compose.demo.yml writes it (taken by `docker run -e NAME` from this environment, never on a
# command line)
password=$(openssl rand -hex 12)
MAILPIT_UI_PASSWORD_HASH=$(printf '%s\n' "$password" | docker run --rm -i "$CADDY_IMAGE" caddy hash-password | tr -d '\r')
MP_UI_AUTH=demo:$MAILPIT_UI_PASSWORD_HASH
export MP_UI_AUTH

docker network create "$NAME" > /dev/null
# the shared services, as echo upstreams under their service names
for service in keycloak:8080 grafana-lgtm:3000 rabbitmq:15672; do
  MSYS_NO_PATHCONV=1 docker run -d --name "$NAME-${service%:*}" --network "$NAME" --network-alias "${service%:*}" \
    -e PORT="${service#*:}" -e STAND_IN_NAME="${service%:*}" \
    -v "$(host_path "$PWD/tests/fixtures/stand-in-upstream"):/stand-in:ro" \
    "$CADDY_IMAGE" caddy run --config /stand-in/http.caddy --adapter caddyfile > /dev/null
done
# Turu's MCP server, under its demo name (intent 0013), and Turu's site as register-app.sh generates it
MSYS_NO_PATHCONV=1 docker run -d --name "$NAME-turu-mcp" --network "$NAME" --network-alias turu.mcp \
  -e PORT=9080 -e STAND_IN_NAME=turu-mcp -v "$(host_path "$PWD/tests/fixtures/0013"):/stand-in:ro" \
  "$CADDY_IMAGE" caddy run --config /stand-in/forwarded-upstream.caddy --adapter caddyfile > /dev/null
bash routes.sh generate examples/routes/turu.routes turu demo > "$work/apps/turu.caddy"
# Mailpit, the stack's image (compose.yml), under its web root as on the demo host
MSYS_NO_PATHCONV=1 docker run -d --name "$NAME-mailpit" --network "$NAME" --network-alias mailpit \
  -e MP_WEBROOT=/mailpit/ -e MP_UI_AUTH axllent/mailpit:v1.31.0 > /dev/null
# the demo configuration as it is, under a wrapper that only swaps Let's Encrypt for Caddy's own CA;
# Caddy has no Mailpit credential
printf '{\n\tlocal_certs\n\tskip_install_trust\n}\n\nimport /etc/caddy/Caddyfile\n' > "$work/test/Caddyfile"
MSYS_NO_PATHCONV=1 docker run -d --name "$NAME-caddy" --network "$NAME" -p "127.0.0.1:$PORT:443" \
  -e INFRA_ENV=demo -e INFRA_HOST="$HOST" \
  -v "$(host_path "$PWD/caddy"):/etc/caddy:ro" -v "$(host_path "$work/apps"):/etc/caddy/apps:ro" \
  -v "$(host_path "$work/test"):/test:ro" \
  "$PROXY_IMAGE" caddy run --config /test/Caddyfile --adapter caddyfile > /dev/null

# Requests https://<host>:$PORT<path>: sets $work/code, $work/headers (no \r) and $work/body
fetch_on() { # <host> <path> [curl option…]
  local host=$1 path=$2
  shift 2
  curl --ssl-no-revoke -sk --resolve "$host:$PORT:127.0.0.1" -D "$work/headers.raw" -o "$work/body" \
    -w '%{http_code}' "$@" "https://$host:$PORT$path" > "$work/code"
  tr -d '\r' < "$work/headers.raw" > "$work/headers"
}
fetch() { # <path> [curl option…]: on $HOST
  fetch_on "$HOST" "$@"
}

answered() { # <status>
  [ "$(cat "$work/code")" = "$1" ] || { echo "status $(cat "$work/code"), body:"; cat "$work/body"; return 1; }
}

body_holds() { # <text>
  grep -qF -- "$1" "$work/body" || { echo "body:"; cat "$work/body"; return 1; }
}

body_is() { # <text>: the whole body (an echo stand-in's one line)
  [ "$(cat "$work/body")" = "$1" ] || { echo "body:"; cat "$work/body"; return 1; }
}

header_is() { # <name> <value>
  grep -qix -- "$1: $2" "$work/headers" || { echo "headers:"; cat "$work/headers"; return 1; }
}

no_header() { # <name>
  ! grep -qi -- "^$1:" "$work/headers" || { echo "headers:"; cat "$work/headers"; return 1; }
}

waited=0
until fetch /auth/ && [ "$(cat "$work/code")" = 200 ] && fetch /mailpit/readyz && [ "$(cat "$work/code")" = 200 ]; do
  if [ "$waited" -ge 30 ]; then
    echo "the demo Caddy doesn't answer; its log:"
    docker logs --tail 20 "$NAME-caddy"
    break
  fi
  sleep 1
  waited=$((waited + 1))
done

# AC-03
fetch /mailpit/
check "/mailpit/ without credentials: 401" answered 401
fetch /mailpit/ -u "demo:wrong"
check "/mailpit/ with a wrong password: 401" answered 401
printf 'user = "demo:%s"\n' "$password" > "$work/credentials"
fetch /mailpit/ -K "$work/credentials"
check "/mailpit/ with the credentials: 200" answered 200
check "/mailpit/ with the credentials: answered by Mailpit (its page)" body_holds '<title>Mailpit</title>'
fetch /rabbitmq/
check "/rabbitmq/: 404" answered 404
check "/rabbitmq/: not RabbitMQ's" body_holds 'c4-infra: the applications are on their own host names'
fetch /
check "/: 404 (no landing page on the demo host)" answered 404

# the headers every site sends, HSTS on the demo host
fetch /auth/realms/faito
check "/auth/realms/faito: answered by Keycloak" body_is 'upstream=keycloak host=infra.c4-soft.com uri=/auth/realms/faito'
check "HSTS" header_is Strict-Transport-Security 'max-age=31536000; includeSubDomains'
check "X-Content-Type-Options" header_is X-Content-Type-Options nosniff
check "Referrer-Policy" header_is Referrer-Policy strict-origin-when-cross-origin
check "no Server header" no_header Server
check "no single-page-app CSP on the shared host" no_header Content-Security-Policy
fetch /grafana/
check "/grafana/: answered by Grafana" body_holds 'upstream=grafana-lgtm '

# AC-06
fetch /.well-known/openid-configuration/auth/realms/faito
check "realm discovery (openid-configuration): 200" answered 200
check "realm discovery (openid-configuration): rewritten for Keycloak" \
  body_is 'upstream=keycloak host=infra.c4-soft.com uri=/auth/realms/faito/.well-known/openid-configuration'
fetch /.well-known/oauth-authorization-server/auth/realms/faito
check "realm discovery (oauth-authorization-server): rewritten for Keycloak" \
  body_is 'upstream=keycloak host=infra.c4-soft.com uri=/auth/realms/faito/.well-known/oauth-authorization-server'

# AC-06 (intent 0013): Turu's MCP origin, its MCP server only, with the headers it derives its
# protected resource's URL from
fetch_on turu-mcp.c4-soft.com /mcp
check "0013: turu-mcp.c4-soft.com/mcp: answered by Turu's MCP server (turu.mcp:9080)" answered 200
check "0013: sent the client's Host, X-Forwarded-Host and X-Forwarded-Proto" \
  body_is "upstream=turu-mcp host=turu-mcp.c4-soft.com uri=/mcp x-forwarded-host=turu-mcp.c4-soft.com:$PORT x-forwarded-proto=https"
check "0013: HSTS on the MCP origin" header_is Strict-Transport-Security 'max-age=31536000; includeSubDomains'
check "0013: no single-page-app CSP on the MCP origin" no_header Content-Security-Policy
fetch_on turu-mcp.c4-soft.com /.well-known/oauth-protected-resource/mcp
check "0013: its protected resource's document, from Turu's MCP server" \
  body_holds 'upstream=turu-mcp host=turu-mcp.c4-soft.com uri=/.well-known/oauth-protected-resource/mcp '
fetch_on turu-mcp.c4-soft.com /fr/
check "0013: the MCP origin serves no front end (404)" answered 404
fetch_on turu.c4-soft.com /mcp
check "0013: turu.c4-soft.com serves no MCP route (404)" answered 404
finish
