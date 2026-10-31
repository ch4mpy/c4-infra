#!/usr/bin/env bash
# 0015: the headers a front end's browser receives through the shared proxy, with and without
# headers=app, and those of the responses the proxy makes itself: two throwaway proxies of the stack's
# image running caddy/ as it is, one with INFRA_ENV=dev (the workstation's certificate), one with
# INFRA_ENV=demo (under a wrapper that only swaps Let's Encrypt for Caddy's own CA, as
# tests/0003-demo-edge.sh), each serving the sites routes.sh generates from tests/fixtures/0015/ (with
# the demo's upstreams: service names, in both, since only the environment's snippets differ), in
# front of verif's front end (tests/fixtures/0015/frontend.caddy); verif's gateway, verif-down's
# front end and Keycloak don't answer.
#
#   - AC-01: /fr/x (headers=app, a front end sending its policy and X-Frame-Options): each of the
#     three headers once, the front end's values, the shared Permissions-Policy it doesn't send;
#   - AC-02: /en/x (sending none): the three shared values; /report-only/x: the shared policy
#     enforced, beside the front end's report-only one;
#   - AC-03: a 2 KB POST on /fr/upload/x (max-body=1KB): 413 with the three shared values; /down/x of
#     verif-down: 502 with them;
#   - AC-04: on /fr/x, nosniff, Referrer-Policy strict-origin-when-cross-origin (the front end's
#     unsafe-url replaced), no Server; HSTS on the demo only;
#   - AC-05: /ui/x (no headers=app, a front end sending its own policy): today's headers, two
#     policies, the shared one first;
#   - 0031: /own/x (fr) and /ui-own/x (ui), headers=app, a front end sending all three: each once,
#     with the front end's value, its Permissions-Policy included;
#   - AC-08: the proxy's own responses, verif's gateway 502, /ui-down/x's 502, /ui-upload/x's 413, the
#     shared host's 502: nosniff, Referrer-Policy, no Server, HSTS on the demo only; the front ends'
#     (without headers=app) keep the three shared values; the proxy logs each, with its cause, and
#     not a request it served;
#   - AC-06: register-app.sh with headers=app on the gateway refused in dev, naming the line, before
#     any docker call (a fake docker).
#
#   bash tests/0015-headers.sh
#
# Needs the image c4-infra/reverse-proxy and certs/tls.crt (up.sh makes both). Its containers and
# network are removed whatever happens.
#
# covers: caddy/ routes.sh registry.sh register-app.sh reverse-proxy/ tests/fixtures/0015/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/docker-preflight.sh
mapfile -t C4_LABELS < <(docker_labels c4-infra)
source tests/lib/stubs.sh

PROXY_IMAGE=c4-infra/reverse-proxy
UPSTREAM_IMAGE=caddy:2.11.4-alpine
NAME=c4-infra-test-0015-headers
HOST=infra.c4-soft.com
DEV_PORT=48451
DEMO_PORT=48452
FIXTURES=tests/fixtures/0015
export REGISTRY_FILE=$PWD/$FIXTURES/registry.txt
SHARED_CSP="default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; font-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'; object-src 'none'"
SHARED_PERMISSIONS='camera=(), microphone=(), geolocation=(), payment=()'
OWN_CSP="default-src 'none'; script-src 'self' 'sha256-verif'"
OWN_PERMISSIONS='geolocation=(self "https://tiles.verif.example"), fullscreen=(self)'

host_path() { if command -v cygpath > /dev/null; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

work=$(mktemp -d)
cleanup() {
  docker rm -f -v $(docker ps -aq -f "name=^$NAME-") > /dev/null 2>&1
  docker network rm "$NAME" > /dev/null 2>&1
  rm -rf "$work"
}
trap cleanup EXIT
cleanup
mkdir -p "$work/apps" "$work/test"

for app in verif verif-down; do
  bash routes.sh generate "$FIXTURES/$app.routes" "$app" demo > "$work/apps/$app.caddy" \
    || { echo "routes.sh refuses $FIXTURES/$app.routes"; exit 1; }
done
printf '{\n\tlocal_certs\n\tskip_install_trust\n}\n\nimport /etc/caddy/Caddyfile\n' > "$work/test/Caddyfile"

docker network create "${C4_LABELS[@]}" "$NAME" > /dev/null
MSYS_NO_PATHCONV=1 docker run "${C4_LABELS[@]}" -d --name "$NAME-frontend" --network "$NAME" --network-alias verif.frontend \
  -v "$(host_path "$PWD/$FIXTURES"):/fixture:ro" "$UPSTREAM_IMAGE" caddy run --config /fixture/frontend.caddy --adapter caddyfile > /dev/null
MSYS_NO_PATHCONV=1 docker run "${C4_LABELS[@]}" -d --name "$NAME-dev" --network "$NAME" -p "127.0.0.1:$DEV_PORT:443" \
  -e INFRA_ENV=dev -e INFRA_HOST="$HOST" \
  -v "$(host_path "$PWD/caddy"):/etc/caddy:ro" -v "$(host_path "$work/apps"):/etc/caddy/apps:ro" \
  -v "$(host_path "$PWD/certs"):/certs:ro" \
  "$PROXY_IMAGE" caddy run --config /etc/caddy/Caddyfile --adapter caddyfile > /dev/null
MSYS_NO_PATHCONV=1 docker run "${C4_LABELS[@]}" -d --name "$NAME-demo" --network "$NAME" -p "127.0.0.1:$DEMO_PORT:443" \
  -e INFRA_ENV=demo -e INFRA_HOST="$HOST" \
  -v "$(host_path "$PWD/caddy"):/etc/caddy:ro" -v "$(host_path "$work/apps"):/etc/caddy/apps:ro" \
  -v "$(host_path "$work/test"):/test:ro" \
  "$PROXY_IMAGE" caddy run --config /test/Caddyfile --adapter caddyfile > /dev/null

# <host> <path> [curl option…], on $port: the status in $work/code, the headers (lower-case names, no
# \r) in $work/headers, the body in $work/body
fetch() {
  local host=$1 path=$2
  shift 2
  curl --ssl-no-revoke -sk --resolve "$host:$port:127.0.0.1" -D "$work/headers.raw" -o "$work/body" \
    -w '%{http_code}' "$@" "https://$host:$port$path" > "$work/code"
  tr -d '\r' < "$work/headers.raw" \
    | awk 'index($0, ":") > 1 { name = tolower(substr($0, 1, index($0, ":") - 1)); print name ": " substr($0, index($0, ":") + 2) }' \
    > "$work/headers"
}
answered() { # <status>
  [ "$(cat "$work/code")" = "$1" ] || { echo "status $(cat "$work/code"), headers:"; cat "$work/headers"; return 1; }
}
values() { sed -n "s/^$1: //p" "$work/headers"; }
once() { # <name> <value>: the header once, with that value
  [ "$(values "$1" | wc -l)" -eq 1 ] && [ "$(values "$1")" = "$2" ] \
    || { echo "$1:"; values "$1"; return 1; }
}
absent() { # <name>
  [ -z "$(values "$1")" ] || { echo "$1:"; values "$1"; return 1; }
}
shared_three() {
  once content-security-policy "$SHARED_CSP" && once x-frame-options DENY && once permissions-policy "$SHARED_PERMISSIONS"
}
common() { # <dev|demo>: what every response of every site carries
  once x-content-type-options nosniff && once referrer-policy strict-origin-when-cross-origin && absent server || return 1
  if [ "$1" = demo ]; then
    once strict-transport-security 'max-age=31536000; includeSubDomains'
  else
    absent strict-transport-security
  fi
}
logged() { # <text> <text>: a line of the proxy's log holds both
  docker logs "$NAME-$env" 2>&1 | grep -F -- "$1" | grep -qF -- "$2" \
    || { echo "log:"; docker logs --tail 5 "$NAME-$env" 2>&1 | cut -c1-300; return 1; }
}
ready() {
  local waited
  for ((waited = 0; waited < 40; waited++)); do
    fetch verif.c4-soft.com /en/x
    [ "$(cat "$work/code")" = 200 ] && return 0
    sleep 0.5
  done
  echo "the $env proxy doesn't answer; its log:"
  docker logs --tail 15 "$NAME-$env" 2>&1
  return 1
}

head -c 2048 /dev/zero | tr '\0' x > "$work/2kb"
for env in dev demo; do
  if [ "$env" = dev ]; then port=$DEV_PORT; else port=$DEMO_PORT; fi
  check "$env: the throwaway proxy answers" ready

  fetch verif.c4-soft.com /fr/x
  check "$env, AC-01: /fr/x answered by the front end" answered 200
  check "$env, AC-01: its Content-Security-Policy, once" once content-security-policy "$OWN_CSP"
  check "$env, AC-01: its X-Frame-Options, once" once x-frame-options SAMEORIGIN
  check "$env, AC-01: the shared Permissions-Policy it doesn't send, once" once permissions-policy "$SHARED_PERMISSIONS"
  check "$env, AC-04: nosniff, Referrer-Policy (its unsafe-url replaced), no Server, HSTS on the demo only" common "$env"

  fetch verif.c4-soft.com /en/x
  check "$env, AC-02: a front end sending none: the three shared values" shared_three
  fetch verif.c4-soft.com /report-only/x
  check "$env, AC-02: a report-only policy: the shared one enforced" once content-security-policy "$SHARED_CSP"
  check "$env, AC-02: and the front end's report-only one" \
    once content-security-policy-report-only "default-src 'none'; report-to verif"

  fetch verif.c4-soft.com /fr/upload/x -X POST --data-binary "@$work/2kb" -H 'Content-Type: text/plain'
  check "$env, AC-03: 2 KB on /fr/upload/x (max-body=1KB): 413" answered 413
  check "$env, AC-03: the 413 carries the three shared values" shared_three
  check "$env, AC-08: and the common headers" common "$env"
  fetch verif-down.c4-soft.com /down/x
  check "$env, AC-03: a front end that doesn't answer (headers=app): 502" answered 502
  check "$env, AC-03: the 502 carries the three shared values" shared_three
  check "$env, AC-08: and the common headers" common "$env"

  fetch verif.c4-soft.com /ui/x
  check "$env, AC-05: /ui/x (no headers=app): two policies, today's" \
    eval '[ "$(values content-security-policy | wc -l)" -eq 2 ]'
  check "$env, AC-05: the shared one first" eval '[ "$(values content-security-policy | head -n 1)" = "$SHARED_CSP" ]'
  check "$env, AC-05: two X-Frame-Options" eval '[ "$(values x-frame-options | LC_ALL=C sort | paste -sd" " -)" = "DENY SAMEORIGIN" ]'

  for path in /own/x /ui-own/x; do
    fetch verif.c4-soft.com "$path"
    check "$env, 0031: $path (headers=app, sending all three): answered by the front end" answered 200
    check "$env, 0031: $path: its Content-Security-Policy, once" once content-security-policy "$OWN_CSP"
    check "$env, 0031: $path: its X-Frame-Options, once" once x-frame-options SAMEORIGIN
    check "$env, 0031: $path: its Permissions-Policy, once" once permissions-policy "$OWN_PERMISSIONS"
  done

  fetch verif.c4-soft.com /gateway/x
  check "$env, AC-08: a gateway that doesn't answer: 502" answered 502
  check "$env, AC-08: the gateway's 502 carries the common headers" common "$env"
  fetch verif-down.c4-soft.com /ui-down/x
  check "$env, AC-08: a ui front end that doesn't answer: 502" answered 502
  check "$env, AC-08: its 502 carries the common headers" common "$env"
  check "$env, AC-05: and the three shared values, as before" shared_three
  fetch verif.c4-soft.com /ui-upload/x -X POST --data-binary "@$work/2kb" -H 'Content-Type: text/plain'
  check "$env, AC-08: 2 KB on /ui-upload/x: 413" answered 413
  check "$env, AC-08: the 413 carries the common headers" common "$env"
  check "$env, AC-05: and the three shared values, as before" shared_three
  fetch "$HOST" /auth/realms/verif
  check "$env, AC-08: the shared host's Keycloak doesn't answer: 502" answered 502
  check "$env, AC-08: its 502 carries the common headers" common "$env"
  check "$env: the proxy logs the gateway's 502 with its cause" logged '"uri":"/gateway/x"' '"error":"dial tcp: lookup verif.gateway'
  check "$env: and not a request it served (/fr/x)" eval '! docker logs "$NAME-$env" 2>&1 | grep -F "\"uri\":\"/fr/x\""'
done

# AC-06: refused in dev before anything is registered
stub_path "$work/stubs" docker
: > "$work/docker.log"
STUB_LOG="$work/docker.log" PATH="$work/stubs:$PATH" \
  bash ./register-app.sh --app verif --proxy "$FIXTURES/refused-gateway.routes" > "$work/register.out" 2>&1 < /dev/null
status=$?
check "AC-06: headers=app on the gateway: register-app.sh exits 1 (exit $status)" test "$status" -eq 1
check "AC-06: naming the file and line" \
  grep -qF 'refused-gateway.routes:3: headers=app is for a front end (fr, en or ui), not for gateway' "$work/register.out"
check "AC-06: before any docker call" test ! -s "$work/docker.log"
finish
