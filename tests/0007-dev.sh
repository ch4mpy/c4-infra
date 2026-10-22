#!/usr/bin/env bash
# 0007: on the workstation, the dev stack's networks and RabbitMQ's loopback (REQ-8, REQ-10), against
# the running stack (bash up.sh).
#
#   bash tests/0007-dev.sh [rabbitmq]...   (every part by default)
#
#   rabbitmq  AC-11: Faito's deployment (bash ../faito/deploy-dev.sh, FAITO_DIR to change it) imports
#             its RabbitMQ user faito-api with rabbitmqctl in the container; RabbitMQ is healthy; its
#             node name resolves to 127.0.0.1 first in its container; epmd (4369) and the Erlang
#             distribution (25672) listen on its loopback only
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

RABBITMQ=c4-infra.rabbitmq
FAITO_DIR=${FAITO_DIR:-../faito}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# "<address hex>:<port hex>" of each listening TCP socket of the container (IPv4 and IPv6)
listening_sockets() { # <container>
  MSYS_NO_PATHCONV=1 docker exec "$1" cat /proc/net/tcp /proc/net/tcp6 < /dev/null | tr -d '\r' \
    | awk '$4 == "0A" { print $2 }'
}
# the addresses (hex, as /proc/net/tcp writes them) <port> listens on, sorted, on one line
addresses_of_port() { # <sockets file> <port>
  local hex
  hex=$(printf '%04X' "$2")
  awk -F: -v port="$hex" '$2 == port { print $1 }' "$1" | sort -u | paste -sd' ' -
}

# every address is the loopback's (127.0.0.1 or ::1), 127.0.0.1 among them
loopback_only() { # <addresses, space-separated>
  local address
  [[ " $1 " == *" 127.0.0.1 "* ]] || return 1
  for address in $1; do
    case $address in 127.0.0.1 | ::1) ;; *) return 1 ;; esac
  done
}

part_rabbitmq() {
  local status found
  if [ -f "$FAITO_DIR/deploy-dev.sh" ]; then
    bash "$FAITO_DIR/deploy-dev.sh" > "$work/deploy-dev.log" 2>&1
    status=$?
    check "AC-11: bash $FAITO_DIR/deploy-dev.sh exits 0 (exit $status)" test "$status" -eq 0
    imported() {
      grep -qF 'RabbitMQ: virtual host faito, user faito-api' "$work/deploy-dev.log" \
        || { tail -n 15 "$work/deploy-dev.log"; return 1; }
    }
    check "AC-11: its registration imports faito-api (rabbitmqctl import_definitions in the container)" imported
  else
    echo "# $FAITO_DIR/deploy-dev.sh missing: a registration of Faito's RabbitMQ user instead"
    RABBITMQ_PASSWORD=$(openssl rand -hex 16) bash register-app.sh --app faito --rabbitmq-user faito-api \
      --rabbitmq-password-env RABBITMQ_PASSWORD > "$work/register.log" 2>&1
    check "AC-11: register-app.sh imports faito-api (rabbitmqctl import_definitions in the container)" \
      grep -qF 'RabbitMQ: virtual host faito, user faito-api' "$work/register.log"
  fi
  listed() {
    MSYS_NO_PATHCONV=1 docker exec "$RABBITMQ" rabbitmqctl -q list_users < /dev/null | grep -q '^faito-api'
  }
  check "AC-11: rabbitmqctl lists faito-api" listed
  check "AC-11: $RABBITMQ is healthy (its healthcheck, rabbitmq-diagnostics ping)" \
    test "$(docker inspect -f '{{.State.Health.Status}}' "$RABBITMQ" 2> /dev/null)" = healthy
  found=$(MSYS_NO_PATHCONV=1 docker exec "$RABBITMQ" getent hosts rabbitmq < /dev/null | tr -d '\r' | head -n 1 | awk '{ print $1 }')
  check "its node name's host, rabbitmq, resolves to 127.0.0.1 first in its container (${found:-nothing})" test "$found" = 127.0.0.1
  listening_sockets "$RABBITMQ" > "$work/sockets"
  for port in 4369 25672; do
    found=$(addresses_of_port "$work/sockets" "$port")
    # as /proc/net/tcp{,6} write them: 0100007F is 127.0.0.1, 0…01000000 is ::1 (epmd binds both)
    found=${found//00000000000000000000000001000000/::1}
    found=${found//0100007F/127.0.0.1}
    check "REQ-10: $port listens on the loopback only (${found:-not listening})" loopback_only "$found"
  done
}

[ $# -gt 0 ] || set -- rabbitmq
for part in "$@"; do
  case "$part" in
    rabbitmq)
      echo "# $part"
      "part_$part"
      ;;
    *)
      echo "Unknown part: $part (rabbitmq)" >&2
      exit 2
      ;;
  esac
done
finish
