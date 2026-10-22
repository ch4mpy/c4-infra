#!/usr/bin/env bash
# 0007: on the workstation, each application's network, the dev stack's networks and RabbitMQ's
# loopback (REQ-5, REQ-8, REQ-10), against the running stack (bash up.sh).
#
#   bash tests/0007-dev.sh [rabbitmq|networks|tickee|guard]...   (every part by default)
#
#   rabbitmq  AC-11: Faito's deployment (bash ../faito/deploy-dev.sh, FAITO_DIR to change it) imports
#             its RabbitMQ user faito-api with rabbitmqctl in the container; RabbitMQ is healthy; its
#             node name resolves to 127.0.0.1 first in its container; epmd (4369) and the Erlang
#             distribution (25672) listen on its loopback only
#   networks  AC-10 (dev): Faito registered, c4-infra.faito holds the five shared services and not
#             keycloak-db, which is on c4-infra.keycloak-db only; compose's model has them there too
#   tickee    AC-7: Tickee registered (its network only), an LDAP stand-in on c4-infra.tickee
#             (osixia/openldap:1.5.0, as tickee.ldap-standin): Keycloak connects to it
#             (testLDAPConnection), a container on c4-infra.faito doesn't, by name nor by address;
#             the stand-in removed, and Tickee's network when this test created it
#   guard     compose.apps.yml is the same (cksum) before and after `tests/0001-loopback-ports.sh
#             resolution`, which runs up.sh with a fake docker; with INFRA_ENV=demo (a scratch copy of
#             networks.sh, its .env tests/fixtures/0003/demo.env), `networks.sh compose-file` puts the
#             reverse proxy on each application's network under ${INFRA_HOST} too; dev's doesn't
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/keycloak.sh

RABBITMQ=c4-infra.rabbitmq
FAITO_DIR=${FAITO_DIR:-../faito}
SHARED='c4-infra.grafana-lgtm c4-infra.keycloak c4-infra.mailpit c4-infra.rabbitmq c4-infra.reverse-proxy'
LDAP_IMAGE=osixia/openldap:1.5.0
LDAP=tickee.ldap-standin

work=$(mktemp -d)
remove_tickee=false
cleanup() {
  docker rm -f "$LDAP" > /dev/null 2>&1
  ! $remove_tickee || bash networks.sh remove tickee > /dev/null
  rm -rf "$work"
}
trap cleanup EXIT

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

# The containers of a network, by name, sorted, on one line
network_containers() { # <network>
  docker network inspect -f '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}' "$1" 2> /dev/null | tr -d '\r' \
    | sed '/^$/d' | sort | paste -sd' ' -
}
networks_of() { # <container>: its networks, sorted, on one line
  docker inspect -f '{{range $name, $_ := .NetworkSettings.Networks}}{{$name}}{{"\n"}}{{end}}' "$1" 2> /dev/null \
    | tr -d '\r' | sed '/^$/d' | sort | paste -sd' ' -
}
holds_shared() { # <network>: the five shared services, and not keycloak-db
  local found service
  found=" $(network_containers "$1") "
  for service in $SHARED; do
    [[ $found == *" $service "* ]] || { echo "$1 holds:$found"; return 1; }
  done
  [[ $found != *" c4-infra.keycloak-db "* ]] || { echo "$1 holds:$found"; return 1; }
}
# <word> is one of the space-separated <list>
in_list() { # <word> <list>
  [[ " $2 " == *" $1 "* ]]
}
# the command fails (a refused connection)
fails() {
  if "$@" > /dev/null 2>&1; then
    echo "it succeeded"
    return 1
  fi
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

part_networks() {
  local found model
  register_faito() { bash register-app.sh --app faito > "$work/faito.log" 2>&1 || { cat "$work/faito.log"; return 1; }; }
  check "Faito registers (bash register-app.sh --app faito: its network)" register_faito
  check "AC-10: c4-infra.faito holds the five shared services, not keycloak-db" holds_shared c4-infra.faito
  found=$(networks_of c4-infra.keycloak-db)
  check "AC-10: keycloak-db is on c4-infra.keycloak-db only (${found:-none})" test "$found" = c4-infra.keycloak-db
  found=$(network_containers c4-infra.keycloak-db)
  check "AC-10: c4-infra.keycloak-db holds Keycloak and its database only ($found)" \
    test "$found" = 'c4-infra.keycloak c4-infra.keycloak-db'
  found=$(docker network inspect -f '{{index .Labels "c4-infra.app"}}' c4-infra.faito 2> /dev/null | tr -d '\r')
  check "c4-infra.faito is labelled c4-infra.app=faito ($found)" test "$found" = faito
  model=$(docker compose config --format json)
  found=$(jq -r '.services["keycloak"].networks | keys | join(" ")' <<< "$model")
  check "compose's model: Keycloak on c4-infra.faito ($found)" in_list c4-infra.faito "$found"
  found=$(jq -r '.services["keycloak-db"].networks | keys | join(" ")' <<< "$model")
  check "compose's model: keycloak-db on its network only ($found)" test "$found" = keycloak-db
}

part_tickee() {
  local address output
  docker network inspect c4-infra.tickee > /dev/null 2>&1 || remove_tickee=true
  register_tickee() { bash register-app.sh --app tickee > "$work/tickee.log" 2>&1 || { cat "$work/tickee.log"; return 1; }; }
  check "Tickee registers (bash register-app.sh --app tickee: its network only)" register_tickee
  check "c4-infra.tickee holds the five shared services, not keycloak-db" holds_shared c4-infra.tickee
  docker rm -f "$LDAP" > /dev/null 2>&1
  start_ldap() { docker run -d --name "$LDAP" --network c4-infra.tickee "$LDAP_IMAGE" > /dev/null; }
  check "Tickee's LDAP stand-in starts on c4-infra.tickee ($LDAP, $LDAP_IMAGE)" start_ldap
  ldap_connects() {
    local deadline=$((SECONDS + 90))
    until output=$(kc_admin create testLDAPConnection -r master -s action=testConnection \
      -s "connectionUrl=ldap://$LDAP:389" -s authType=none 2>&1); do
      [ "$SECONDS" -lt "$deadline" ] || { printf '%s\n' "$output" | tail -n 3; return 1; }
      sleep 2
    done
  }
  check "AC-7: Keycloak connects to ldap://$LDAP:389 (testLDAPConnection)" ldap_connects
  check "control: from c4-infra.tickee, $LDAP:389 answers" \
    docker run --rm --network c4-infra.tickee alpine:3 nc -z -w 3 "$LDAP" 389
  check "AC-7: from c4-infra.faito, $LDAP:389 can't be reached by name" \
    fails docker run --rm --network c4-infra.faito alpine:3 nc -z -w 3 "$LDAP" 389
  address=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$LDAP" | tr -d '\r')
  check "$LDAP has an address (${address:-none})" test -n "$address"
  check "AC-7: from c4-infra.faito, $address:389 can't be reached" \
    fails docker run --rm --network c4-infra.faito alpine:3 nc -z -w 3 "$address" 389
  docker rm -f "$LDAP" > /dev/null 2>&1
  check "the stand-in is removed" test -z "$(docker ps -aq -f "name=^$LDAP\$")"
}

part_guard() {
  local before after status scratch model found
  check "compose.apps.yml is there (up.sh)" test -f compose.apps.yml
  before=$(cksum < compose.apps.yml)
  bash tests/0001-loopback-ports.sh resolution > "$work/0001.log" 2>&1
  status=$?
  check "tests/0001-loopback-ports.sh resolution (up.sh with a fake docker) passes (exit $status)" test "$status" -eq 0
  after=$(cksum < compose.apps.yml)
  check "compose.apps.yml is unchanged by it (cksum $before)" test "$after" = "$before"
  # the demo host's: INFRA_ENV=demo, in a scratch copy
  scratch=$work/demo
  mkdir -p "$scratch"
  cp networks.sh registry.sh registry.txt compose.yml compose.demo.yml "$scratch/"
  cp tests/fixtures/0003/demo.env "$scratch/.env"
  check "with INFRA_ENV=demo, networks.sh compose-file runs" bash "$scratch/networks.sh" compose-file
  model=$(cd "$scratch" && docker compose -f compose.yml -f compose.demo.yml -f compose.apps.yml --env-file .env config --format json)
  found=$(jq -r '.services["reverse-proxy"].networks["c4-infra.faito"].aliases // [] | join(" ")' <<< "$model")
  check "demo: the reverse proxy is on c4-infra.faito under infra.c4-soft.com (INFRA_HOST) too (${found:-no alias})" \
    in_list infra.c4-soft.com "$found"
  found=$(jq -r '.services["keycloak-db"].networks | keys | join(" ")' <<< "$model")
  check "demo: keycloak-db on its network only ($found)" test "$found" = keycloak-db
  found=$(docker compose config --format json | jq -r '.services["reverse-proxy"].networks["c4-infra.faito"].aliases // [] | join(" ")')
  check "dev: the reverse proxy has no INFRA_HOST alias on c4-infra.faito (${found:-no alias})" \
    fails in_list host.docker.internal "$found"
}

[ $# -gt 0 ] || set -- rabbitmq networks tickee guard
for part in "$@"; do
  case "$part" in
    rabbitmq | networks | tickee | guard)
      echo "# $part"
      "part_$part"
      ;;
    *)
      echo "Unknown part: $part (rabbitmq, networks, tickee or guard)" >&2
      exit 2
      ;;
  esac
done
finish
