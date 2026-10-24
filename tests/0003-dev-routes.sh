#!/usr/bin/env bash
# 0003: the dev stack's Caddy serves the sites generated from routes files (REQ-3, REQ-4), against
# the running stack (bash up.sh). Two fixture applications of tests/fixtures/0003/registry.txt are
# registered, verif (i18n, block 47xxx) and verif-ui (no i18n, block 46xxx), in front of echo
# stand-ins on the workstation's loopback, which answer their name, the Host they were sent and the
# URI: the gateway over HTTPS with the shared leaf (checked against the local CA), the front ends
# over HTTP. Then Hurura'a and Turu register from their example routes files (AC-9, dev), Turu's MCP
# server on its own origin, turu-mcp.dev.localhost, in front of an echo stand-in on 11280 (intent 0013).
#
#   bash tests/0003-dev-routes.sh
#
# Leaves the stack as it found it: the sites it installed are removed (a site that was there before
# is put back), Caddy reloaded, the landing page rewritten, the stand-ins removed.
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

FIXTURES=tests/fixtures/0003
CADDY_IMAGE=caddy:2.11.4-alpine
STAND_IN=c4-infra-test-routes
SITES=(verif verif-ui hururaa turu)
CSP_FONTS="font-src 'self'"

host_path() {
  if command -v cygpath > /dev/null; then cygpath -w "$1"; else printf '%s' "$1"; fi
}

work=$(mktemp -d)
mkdir -p "$work/before"
# the applications whose network (0007: each registration makes sure of it) this test creates
new_networks=()
for app in "${SITES[@]}"; do
  [ ! -f "caddy/apps/$app.caddy" ] || cp "caddy/apps/$app.caddy" "$work/before/"
  docker network inspect "c4-infra.$app" > /dev/null 2>&1 || new_networks+=("$app")
done
cleanup() {
  local app
  for app in "${SITES[@]}"; do
    if [ -f "$work/before/$app.caddy" ]; then
      cp "$work/before/$app.caddy" "caddy/apps/$app.caddy"
    else
      rm -f "caddy/apps/$app.caddy"
    fi
  done
  for app in "${new_networks[@]}"; do
    bash networks.sh remove "$app" > /dev/null
  done
  MSYS_NO_PATHCONV=1 docker exec c4-infra.reverse-proxy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile > /dev/null 2>&1
  bash register-app.sh --index-only
  docker rm -f $(docker ps -aq -f "name=^$STAND_IN-") > /dev/null 2>&1
  rm -rf "$work"
}
trap cleanup EXIT

# An echo stand-in on 127.0.0.1:<port> (https: with the shared leaf)
stand_in() { # <name> <port> <http|https>
  MSYS_NO_PATHCONV=1 docker run -d --name "$STAND_IN-$2" -p "127.0.0.1:$2:$2" -e PORT="$2" -e STAND_IN_NAME="$1" \
    -v "$(host_path "$PWD/tests/fixtures/stand-in-upstream"):/stand-in:ro" -v "$(host_path "$PWD/certs"):/certs:ro" \
    "$CADDY_IMAGE" caddy run --config "/stand-in/$3.caddy" --adapter caddyfile > /dev/null
}

docker rm -f $(docker ps -aq -f "name=^$STAND_IN-") > /dev/null 2>&1
stand_in verif-gateway 47080 https
stand_in verif-fr 47200 http
stand_in verif-en 47205 http
stand_in verif-ui 46200 http
# Turu's MCP server (block 11xxx): its MCP origin (intent 0013)
stand_in turu-mcp 11280 https
waited=0
until curl -s -o /dev/null http://127.0.0.1:46200/ && curl -sk -o /dev/null https://127.0.0.1:47080/ \
  && curl -sk -o /dev/null https://127.0.0.1:11280/; do
  [ "$waited" -lt 30 ] || break
  sleep 1
  waited=$((waited + 1))
done

# Requests https://<host><path> through the dev proxy: sets $work/code, $work/headers (no \r),
# $work/body and $work/location
fetch() { # <host> <path> [curl option…]
  local host=$1 path=$2
  shift 2
  curl --ssl-no-revoke --cacert certs/ca.crt -s --resolve "$host:443:127.0.0.1" -D "$work/headers.raw" \
    -o "$work/body" -w '%{http_code} %{redirect_url}' "$@" "https://$host$path" > "$work/answer"
  tr -d '\r' < "$work/headers.raw" > "$work/headers"
}

answered() { # <status> [<redirect URL>]
  local expected="$1 ${2:-}"
  [ "$(cat "$work/answer")" = "$expected" ] || { echo "answer: $(cat "$work/answer"); body:"; head -c 300 "$work/body"; return 1; }
}

served_by() { # <stand-in name> <host> <uri>: the echo stand-in's line
  local expected="upstream=$1 host=$2 uri=$3"
  [ "$(cat "$work/body")" = "$expected" ] || { echo "body: $(head -c 300 "$work/body")"; return 1; }
}

header_holds() { # <name> <text>
  grep -i -- "^$1:" "$work/headers" | grep -qF -- "$2" || { echo "headers:"; cat "$work/headers"; return 1; }
}

no_header() { # <name>
  ! grep -qi -- "^$1:" "$work/headers" || { echo "headers:"; cat "$work/headers"; return 1; }
}

registered() { # <registry file, "" for registry.txt> <app> <routes file>
  if [ -n "$1" ]; then
    REGISTRY_FILE=$1 bash register-app.sh --app "$2" --proxy "$3"
  else
    bash register-app.sh --app "$2" --proxy "$3"
  fi
}

check "verif registers from its routes file" registered "$FIXTURES/registry.txt" verif "$FIXTURES/verif.routes"
check "verif-ui registers from its routes file" registered "$FIXTURES/registry.txt" verif-ui "$FIXTURES/verif-ui.routes"
check "verif's site names verif.dev.localhost (INFRA_ENV=dev)" grep -q '^verif.dev.localhost {$' caddy/apps/verif.caddy

# AC-4: the template served, each role to its port of the block
fetch verif.dev.localhost /gateway/x
check "/gateway/x: 200" answered 200
check "/gateway/x: the HTTPS gateway (47080), sent the client's Host" served_by verif-gateway verif.dev.localhost /gateway/x
check "/gateway/x: no single-page-app CSP" no_header Content-Security-Policy
fetch verif.dev.localhost /fr/x
check "/fr/x: the fr front end (47200)" served_by verif-fr verif.dev.localhost /fr/x
# AC-1 (headers): the demo's single-page-app headers, in dev
check "/fr/x: a CSP holding $CSP_FONTS" header_holds Content-Security-Policy "$CSP_FONTS"
check "/fr/x: X-Frame-Options DENY" header_holds X-Frame-Options DENY
check "/fr/x: Permissions-Policy" header_holds Permissions-Policy 'camera=()'
check "/fr/x: X-Content-Type-Options" header_holds X-Content-Type-Options nosniff
check "/fr/x: Referrer-Policy" header_holds Referrer-Policy strict-origin-when-cross-origin
check "/fr/x: no Server header" no_header Server
fetch verif.dev.localhost /en/x
check "/en/x: the en front end (47205)" served_by verif-en verif.dev.localhost /en/x
check "/en/x: a CSP holding $CSP_FONTS" header_holds Content-Security-Policy "$CSP_FONTS"
fetch verif.dev.localhost /
check "/: 302 to /fr/" answered 302 https://verif.dev.localhost/fr/
fetch verif.dev.localhost /fr
check "/fr: 301 to /fr/" answered 301 https://verif.dev.localhost/fr/
fetch verif.dev.localhost /nothing
check "/nothing: 404" answered 404

# first match, in the file's order: the regex route (1 KB) before /gateway/*
head -c 2000 /dev/zero | tr '\0' a > "$work/2KB"
fetch verif.dev.localhost /gateway/upload/x --data-binary @"$work/2KB"
check "a 2 KB POST to the regex route (max-body=1KB): 413" answered 413
fetch verif.dev.localhost /gateway/other --data-binary @"$work/2KB"
check "a 2 KB POST to /gateway/other (no limit): 200" answered 200
check "a 2 KB POST to /gateway/other: the gateway" served_by verif-gateway verif.dev.localhost /gateway/other
fetch verif.dev.localhost /gateway/upload/x --data-binary 'small'
check "a small POST to the regex route: the gateway" served_by verif-gateway verif.dev.localhost /gateway/upload/x

# AC-11: a project without i18n
fetch verif-ui.dev.localhost /ui/x
check "verif-ui /ui/x: the ui front end (46200)" served_by verif-ui verif-ui.dev.localhost /ui/x
check "verif-ui /ui/x: a CSP" header_holds Content-Security-Policy "$CSP_FONTS"
fetch verif-ui.dev.localhost /
check "verif-ui /: 302 to /ui/" answered 302 https://verif-ui.dev.localhost/ui/

# AC-2: no HSTS in dev
fetch faito.dev.localhost /
check "faito.dev.localhost/: answered by its site (302 to /fr/)" answered 302 https://faito.dev.localhost/fr/
check "faito.dev.localhost/: no Strict-Transport-Security" no_header Strict-Transport-Security
fetch host.docker.internal /
check "host.docker.internal/: the landing page" answered 200
check "host.docker.internal/: no Strict-Transport-Security" no_header Strict-Transport-Security
check "the landing page links verif" grep -qF 'https://verif.dev.localhost/' caddy/html/index.html

# AC-6, dev: the realm discovery, from Keycloak
fetch host.docker.internal /.well-known/openid-configuration/auth/realms/faito
check "realm discovery of faito: 200" answered 200
check "realm discovery of faito: Keycloak's issuer" grep -qF '"issuer":"https://host.docker.internal/auth/realms/faito"' "$work/body"
# the shared services, dev's additions included (REQ-2)
fetch host.docker.internal /rabbitmq/
check "/rabbitmq/: 200 (dev)" answered 200
fetch host.docker.internal /mailpit/
check "/mailpit/: 200, no authentication (dev)" answered 200
fetch host.docker.internal /auth/realms/faito
check "/auth/realms/faito: 200" answered 200

# AC-9, dev: Hurura'a and Turu register from their example routes files
check "hururaa registers from examples/routes/hururaa.routes" registered "" hururaa examples/routes/hururaa.routes
check "turu registers from examples/routes/turu.routes" registered "" turu examples/routes/turu.routes
check "turu's site names turu.dev.localhost" grep -q '^turu.dev.localhost {$' caddy/apps/turu.caddy
check "0013: and its MCP origin, turu-mcp.dev.localhost" grep -q '^turu-mcp.dev.localhost {$' caddy/apps/turu.caddy
fetch turu-mcp.dev.localhost /mcp
check "0013: turu-mcp.dev.localhost/mcp: the HTTPS MCP server (11280), sent the client's Host" \
  served_by turu-mcp turu-mcp.dev.localhost /mcp
check "0013: no single-page-app CSP on the MCP origin" no_header Content-Security-Policy
fetch turu-mcp.dev.localhost /fr/
check "0013: the MCP origin serves no front end (404)" answered 404
fetch turu.dev.localhost /mcp
check "0013: turu.dev.localhost serves no MCP route (404)" answered 404
finish
