#!/usr/bin/env bash
# 0013: what a registration refuses since 0013 (RQ-11, RQ-17), on the workstation, with a fake
# docker (tests/lib/stubs.sh): each refusal says why, before any docker call.
#
#   - AC-15: a realm export whose client profile holds a client-id-metadata-document executor that
#     allows the http scheme (true, and each form Keycloak reads as true: "true", "TRUE", 1), or
#     permits the domain * or *. (which matches every host written with a final dot, Keycloak
#     26.8.1: tests/0013-keycloak-facts.sh): Keycloak would fetch any URL an unauthenticated client
#     names, other applications' containers included; its twins, http off (false, "false") with
#     *.example.org and a named domain, pass the check (docker is called);
#   - AC-08: a --proxy file that is an nginx server block (.conf): refused by the routes notation,
#     as any file that isn't a routes file, since the transition is gone.
#
#   bash tests/0013-register.sh
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/stubs.sh

export REGISTRY_FILE=$PWD/tests/fixtures/0013/registry.txt

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
stub_path "$work/stubs" docker

# register-app.sh <option…> with the fake docker first in PATH: sets status, its output in
# $work/out, the docker calls in $work/docker.log
register() {
  : > "$work/docker.log"
  STUB_LOG="$work/docker.log" PATH="$work/stubs:$PATH" \
    bash ./register-app.sh "$@" > "$work/out" 2>&1 < /dev/null
  status=$?
}
refused() {
  [ "$status" -ne 0 ] || { echo "exited 0:"; cat "$work/out"; return 1; }
}
says() { # <text>
  grep -qF -- "$1" "$work/out" || { echo "output:"; cat "$work/out"; return 1; }
}
never_says() { # <text>
  ! grep -qF -- "$1" "$work/out" || { echo "output:"; cat "$work/out"; return 1; }
}
no_docker_call() {
  [ ! -s "$work/docker.log" ] || { echo "docker called:"; head -n 5 "$work/docker.log"; return 1; }
}
refused_before_docker() { # <label> <text the refusal holds>
  check "$1: refused" refused
  check "$1: says \"$2\"" says "$2"
  check "$1: nothing was registered" says "nothing was registered"
  check "$1: before any docker call" no_docker_call
}

# A realm export of verif-delegation's entry: <realm> <the CIMD executor's configuration, JSON>
cimd_realm() {
  printf '{"realm":"%s","enabled":true,"clientProfiles":{"profiles":[{"name":"mcp-clients","executors":[{"executor":"client-id-metadata-document","configuration":%s}]}]}}\n' \
    "$1" "$2" > "$work/$1-realm.json"
  echo "$work/$1-realm.json"
}

# AC-15
register --app verif-delegation --realm "$(cimd_realm verif-cimd-http '{"cimd-allow-http-scheme":true,"cimd-allow-permitted-domains":["*.example.org"]}')"
refused_before_docker "AC-15: http allowed" "client profile mcp-clients: its client-id-metadata-document executor allows the http scheme"
for value in '"true"' '"TRUE"' 1; do
  register --app verif-delegation --realm "$(cimd_realm verif-cimd-http '{"cimd-allow-http-scheme":'"$value"',"cimd-allow-permitted-domains":["*.example.org"]}')"
  refused_before_docker "AC-15: http allowed, as $value" "allows the http scheme (cimd-allow-http-scheme: $value; false only)"
done
register --app verif-delegation --realm "$(cimd_realm verif-cimd-any '{"cimd-allow-permitted-domains":["*"]}')"
refused_before_docker "AC-15: the domain * alone" 'client profile mcp-clients: its client-id-metadata-document executor permits the domain "*"'
register --app verif-delegation --realm "$(cimd_realm verif-cimd-any '{"cimd-allow-permitted-domains":["claude.ai","*."]}')"
refused_before_docker "AC-15: the domain *. (every host written with a final dot)" 'permits the domain "*."'
printf 'not JSON\n' > "$work/verif-cimd-ok-realm.json"
register --app verif-delegation --realm "$work/verif-cimd-ok-realm.json"
refused_before_docker "a realm export that isn't JSON" "not JSON that jq can read"

for value in false '"false"'; do
  register --app verif-delegation --realm "$(cimd_realm verif-cimd-ok '{"cimd-allow-http-scheme":'"$value"',"cimd-allow-permitted-domains":["*.example.org","claude.ai"]}')"
  check "AC-15's twin: http off ($value), *.example.org and a named domain pass the check" never_says "client-id-metadata-document"
  check "AC-15's twin: the registration goes on (docker is called)" test -s "$work/docker.log"
done

# AC-08: the .conf transition is gone
printf 'server {\n  listen 443 ssl;\n  location / { proxy_pass https://host.docker.internal:14200; }\n}\n' > "$work/faito.conf"
register --app faito --proxy "$work/faito.conf"
refused_before_docker "AC-08: a --proxy nginx block (.conf)" "The routes file $work/faito.conf is refused (above)"
check "AC-08: no example routes file replaces it" never_says "examples/routes/faito.routes"

finish
