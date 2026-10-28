#!/usr/bin/env bash
# 0007: the ports each shared service listens on, on its container's every interface, as the demo
# host configures it (AC-09, RQ-10, RQ-11): what an application's network can reach of it.
#
#   bash tests/0007-listeners.sh
#
# Each shared image is started as `docker compose -f compose.yml -f compose.demo.yml --env-file
# tests/fixtures/0003/demo.env config --format json` gives its service: image, command, hostname,
# environment, extra_hosts and mounts (bind mounts as they are, named volumes as anonymous ones),
# under its service name on a throwaway internal network (no way out: the demo Caddy's Let's Encrypt
# never leaves it), as c4probe-<service>, publishing no port. Two values of that fixture only parse,
# and are replaced here through the environment (compose's interpolation prefers it to --env-file):
# KC_IMAGE, the Keycloak image up.sh builds here (c4-infra/keycloak), and MAILPIT_UI_PASSWORD_HASH,
# a bcrypt hash of a random password (caddy hash-password, on stdin). The demo Caddy's
# /etc/caddy/apps is an empty directory: caddy/apps/ holds this workstation's dev sites. Keycloak runs
# on its database, keycloak-db's service started the same way.
#
# Once each one passes its healthcheck (compose's, else its image's) and listens on every port of
# its set, its listening TCP sockets (/proc/net/tcp, /proc/net/tcp6) outside the loopback are
# exactly that set. Everything is removed on exit.
#
# covers: compose.yml compose.demo.yml caddy/ keycloak/ reverse-proxy/ rabbitmq/ grafana-lgtm/
# covers: tests/fixtures/0003/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

PREFIX=c4probe
NETWORK=$PREFIX-net
CADDY_IMAGE=caddy:2.11.4-alpine
SERVICES=(keycloak-db keycloak mailpit rabbitmq grafana-lgtm reverse-proxy)
# AC-09's sets: what answers from an application's network
declare -A EXPECTED=(
  [keycloak]='8080 9000'
  [mailpit]='1025 8025'
  [rabbitmq]='5672 15692'
  [grafana-lgtm]='3000 3100 3200 4040 4317 4318 9090'
  [reverse-proxy]='80 443'
)

host_path() {
  if command -v cygpath > /dev/null; then cygpath -w "$1"; else printf '%s' "$1"; fi
}

work=$(mktemp -d)
cleanup() {
  local service
  for service in "${SERVICES[@]}"; do
    docker rm -f -v "$PREFIX-$service" > /dev/null 2>&1
  done
  docker network rm "$NETWORK" > /dev/null 2>&1
  rm -rf "$work"
}
trap cleanup EXIT
cleanup
work=$(mktemp -d)
mkdir -p "$work/apps"

# "<address> <port>" of each listening TCP socket of the container (IPv4 and IPv6)
listeners() { # <container>
  local sl local_address rest port address
  MSYS_NO_PATHCONV=1 docker exec "$1" cat /proc/net/tcp /proc/net/tcp6 < /dev/null | tr -d '\r' \
    | while read -r sl local_address _ st rest; do
        [ "$st" = 0A ] || continue
        address=${local_address%:*}
        port=$((16#${local_address##*:}))
        case $address in
          00000000) address=0.0.0.0 ;;
          00000000000000000000000000000000) address=:: ;;
          00000000000000000000000001000000) address=::1 ;;
          0000000000000000FFFF0000????????)
            address=${address:24}
            address=::ffff:$((16#${address:6:2})).$((16#${address:4:2})).$((16#${address:2:2})).$((16#${address:0:2}))
            ;;
          ????????) address=$((16#${address:6:2})).$((16#${address:4:2})).$((16#${address:2:2})).$((16#${address:0:2})) ;;
        esac
        echo "$address $port"
      done
}
# the ports a container listens on outside the loopback, sorted, on one line
public_ports() { # <container>
  listeners "$1" | awk '$1 !~ /^127\./ && $1 != "::1" && $1 !~ /^::ffff:127\./ { print $2 }' | sort -n -u | paste -sd' ' -
}

# The demo host's model, with the two values that must start
password=$(openssl rand -hex 12)
MAILPIT_UI_PASSWORD_HASH=$(printf '%s\n' "$password" | docker run --rm -i "$CADDY_IMAGE" caddy hash-password | tr -d '\r')
KC_IMAGE=c4-infra/keycloak
PROXY_IMAGE=c4-infra/reverse-proxy
export MAILPIT_UI_PASSWORD_HASH KC_IMAGE PROXY_IMAGE
docker compose -f compose.yml -f compose.demo.yml --env-file tests/fixtures/0003/demo.env config --format json \
  > "$work/demo.json" 2> "$work/demo.err"
check "the demo host's model is read (compose.yml + compose.demo.yml, tests/fixtures/0003/demo.env)" test -s "$work/demo.json"
check "its Keycloak is c4-infra/keycloak" test "$(jq -r '.services.keycloak.image' "$work/demo.json")" = c4-infra/keycloak

docker network create --internal "$NETWORK" > /dev/null
# Starts <service> as the model says
start() { # <service>
  local service=$1 json image args=() line
  json=$(jq -c --arg s "$service" '.services[$s]' "$work/demo.json")
  image=$(jq -r '.image' <<< "$json")
  jq -r '.environment // {} | to_entries[] | "\(.key)=\(.value)"' <<< "$json" > "$work/$service.env"
  args+=(--env-file "$(host_path "$work/$service.env")")
  line=$(jq -r '.hostname // empty' <<< "$json")
  [ -z "$line" ] || args+=(--hostname "$line")
  while IFS= read -r line; do
    [ -z "$line" ] || args+=(--add-host "$line")
  done < <(jq -r '.extra_hosts // [] | .[]' <<< "$json")
  # (strings, not @tsv: @tsv doubles the backslashes of a Windows path)
  while IFS=$'\t' read -r type source target read_only; do
    case $type in
      bind) args+=(--mount "type=bind,source=$source,target=$target$([ "$read_only" = true ] && echo ,readonly)") ;;
      volume) args+=(--mount "type=volume,target=$target") ;;
    esac
  done < <(jq -r '.volumes // [] | .[] | "\(.type)\t\(.source // "")\t\(.target)\t\(.read_only // false)"' <<< "$json")
  if [ "$service" = reverse-proxy ]; then
    args+=(--mount "type=bind,source=$(host_path "$work/apps"),target=/etc/caddy/apps,readonly")
  fi
  local command=()
  while IFS= read -r line; do
    command+=("$line")
  done < <(jq -r '.command // [] | .[]' <<< "$json")
  MSYS_NO_PATHCONV=1 docker run -d --name "$PREFIX-$service" --network "$NETWORK" --network-alias "$service" \
    "${args[@]}" "$image" "${command[@]}" > /dev/null
}
# compose's healthcheck of <service>, else its image's, run once in its container
healthy() { # <service>
  local service=$1 test kind
  test=$(jq -c --arg s "$service" '.services[$s].healthcheck.test // empty' "$work/demo.json")
  [ -n "$test" ] || test=$(docker image inspect -f '{{json .Config.Healthcheck.Test}}' "$(jq -r --arg s "$service" '.services[$s].image' "$work/demo.json")")
  kind=$(jq -r '.[0]' <<< "$test")
  local argv=()
  while IFS= read -r line; do
    argv+=("$line")
  done < <(jq -r '.[1:] | .[]' <<< "$test")
  case $kind in
    CMD) MSYS_NO_PATHCONV=1 docker exec "$PREFIX-$service" "${argv[@]}" < /dev/null > /dev/null 2>&1 ;;
    CMD-SHELL) MSYS_NO_PATHCONV=1 docker exec "$PREFIX-$service" sh -c "${argv[0]}" < /dev/null > /dev/null 2>&1 ;;
    *) echo "$service: no healthcheck ($test)"; return 1 ;;
  esac
}
# every port of <service>'s set listens (outside the loopback)
all_listening() { # <service>
  local port found
  found=" $(public_ports "$PREFIX-$1") "
  for port in ${EXPECTED[$1]}; do
    [[ $found == *" $port "* ]] || return 1
  done
}
wait_up() { # <service>: healthy, then listening on its whole set; 300 s at most
  local service=$1 deadline=$((SECONDS + 300))
  until healthy "$service"; do
    if [ "$SECONDS" -ge "$deadline" ] || [ "$(docker inspect -f '{{.State.Running}}' "$PREFIX-$service" 2> /dev/null)" != true ]; then
      echo "$PREFIX-$service isn't healthy; its log:"
      docker logs --tail 15 "$PREFIX-$service" 2>&1
      return 1
    fi
    sleep 2
  done
  [ -z "${EXPECTED[$service]:-}" ] && return 0
  until all_listening "$service"; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "$PREFIX-$service listens outside the loopback on: $(public_ports "$PREFIX-$service")"
      return 1
    fi
    sleep 2
  done
}

for service in "${SERVICES[@]}"; do
  check "$service starts ($PREFIX-$service, $(jq -r --arg s "$service" '.services[$s].image' "$work/demo.json"))" start "$service"
done
for service in "${SERVICES[@]}"; do
  check "$service is up (its healthcheck passes)" wait_up "$service"
done
# a last moment for a port that opens late
sleep 5
for service in keycloak mailpit rabbitmq grafana-lgtm reverse-proxy; do
  found=$(public_ports "$PREFIX-$service")
  check "AC-09: $service listens outside its loopback on exactly ${EXPECTED[$service]} (${found:-nothing})" \
    test "$found" = "${EXPECTED[$service]}"
done
finish
