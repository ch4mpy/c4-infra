#!/usr/bin/env bash
# 0043: the five shared services that join the applications' networks (reverse-proxy, keycloak,
# mailpit, rabbitmq, grafana-lgtm) have the stack's own network, c4-infra, as their primary one, which
# no application removes: Docker can't restart a container whose primary network is gone.
#
#   model   the compose model of dev and of the demo, with a compose.apps.yml as networks.sh writes it
#           for an application whose network's key sorts before "default" (c4-infra.aaa): for each
#           of the five, the network compose makes primary (the highest priority, then the first
#           key) is "default"
#   live    the dev stack: each of the five has NetworkMode c4-infra
#
#   bash tests/0043-primary-network.sh [model|live]...   (every part by default)
#
# live needs the dev stack running, as up.sh leaves it.
#
# covers: compose.yml compose.dev.yml compose.demo.yml networks.sh
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

SHARED=(reverse-proxy keycloak mailpit rabbitmq grafana-lgtm)
export MSYS_NO_PATHCONV=1

host_path() { if command -v cygpath > /dev/null; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fake_apps_file() {
  local service
  echo 'services:'
  for service in "${SHARED[@]}"; do
    printf '  %s:\n    networks:\n      c4-infra.aaa: {}\n' "$service"
  done
  printf 'networks:\n  c4-infra.aaa:\n    name: c4-infra.aaa\n    external: true\n'
}

is() { [ "$2" = "$1" ] || { echo "got: $2"; return 1; }; }
primary() { # <model.json> <service>: the key of the network compose makes the service's primary one
  jq -r --arg s "$2" '.services[$s].networks | to_entries | sort_by([-((.value // {}).priority // 0), .key]) | .[0].key' < "$1"
}

part_model() {
  local env service
  fake_apps_file > "$work/apps.yml"
  for env in dev demo; do
    docker compose -f compose.yml -f "compose.$env.yml" -f "$(host_path "$work/apps.yml")" \
      config --no-interpolate --format json > "$work/$env.json" 2> "$work/$env.err"
    check "model, $env: docker compose config renders it" eval '[ -s "$work/$env.json" ] || { cat "$work/$env.err"; false; }'
    for service in "${SHARED[@]}"; do
      check "model, $env: $service's primary network is default, before c4-infra.aaa" \
        is default "$(primary "$work/$env.json" "$service")"
    done
  done
}

part_live() {
  local service
  for service in "${SHARED[@]}"; do
    check "live: c4-infra.$service's NetworkMode is c4-infra" \
      is c4-infra "$(docker inspect -f '{{.HostConfig.NetworkMode}}' "c4-infra.$service" 2>&1 | tr -d '\r')"
  done
}

parts=("$@")
[ ${#parts[@]} -gt 0 ] || parts=(model live)
for part in "${parts[@]}"; do
  case "$part" in
    model|live) "part_$part" ;;
    *) echo "unknown part: $part (model, live)" >&2; exit 2 ;;
  esac
done
finish
