#!/usr/bin/env bash
# 0026: the bound on a container's logs is written twice: compose.yml's x-logging, which every stack
# service references, and demo/c4-app's LOG_BOUND, which `sudo c4-app up` gives every application's
# service. They're the same (RQ-01, RQ-05), read without starting anything:
#
#   bash tests/0026-bound-value.sh
#
# covers: compose.yml demo/c4-app
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

is() { # <actual> <expected>
  [ "$1" = "$2" ] || { echo "actual: $1, expected: $2"; return 1; }
}
config_read() {
  docker compose -f compose.yml config --format json > "$work/config.json" 2> "$work/config.err" \
    || { cat "$work/config.err"; return 1; }
}

check "docker compose -f compose.yml config succeeds" config_read
stack=$(jq -cS '."x-logging"' "$work/config.json")
check "compose.yml's x-logging is json-file 10m × 3 ($stack)" \
  is "$stack" '{"driver":"json-file","options":{"max-file":"3","max-size":"10m"}}'
services=$(jq -cS '[.services[] | .logging] | unique' "$work/config.json")
check "every stack service has it" is "$services" "[$stack]"
sed -n "s/^LOG_BOUND='\(.*\)'\$/\1/p" demo/c4-app > "$work/log-bound"
check "demo/c4-app's LOG_BOUND is read ($(cat "$work/log-bound"))" test "$(wc -l < "$work/log-bound")" -eq 1
check "it is compose.yml's x-logging" is "$(jq -cS . "$work/log-bound")" "$stack"
finish
