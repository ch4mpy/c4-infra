#!/usr/bin/env bash
# 0007: on the workstation, each application's network, the dev stack's networks and RabbitMQ's
# loopback (RQ-05, RQ-08, RQ-10), against the running stack (bash up.sh).
#
#   bash tests/0007-dev.sh [rabbitmq|networks|tickee|guard|rewrite]...   (every part by default)
#
#   rabbitmq  AC-11: Faito's deployment (bash ../faito/deploy-dev.sh, FAITO_DIR to change it) imports
#             its RabbitMQ user faito-api with rabbitmqctl in the container; RabbitMQ is healthy; its
#             node name resolves to 127.0.0.1 first in its container; epmd (4369) and the Erlang
#             distribution (25672) listen on its loopback only
#   networks  AC-10 (dev): Faito registered, c4-infra.faito holds the five shared services and not
#             keycloak-db, which is on c4-infra.keycloak-db only; compose's model has them there too
#   tickee    AC-07 (without LDAP since 0023): Tickee registered (its network only), an HTTP stand-in
#             on c4-infra.tickee (caddy respond, as tickee.network-standin, a container of Tickee's
#             there): Keycloak reaches it, a container on c4-infra.faito doesn't, by name nor by
#             address; the stand-in removed, and Tickee's network when this test created it
#   guard     compose.apps.yml is the same (cksum) before and after `tests/0001-loopback-ports.sh
#             resolution`, which runs up.sh with a fake docker; with INFRA_ENV=demo (a scratch copy of
#             networks.sh, its .env tests/fixtures/0003/demo.env), `networks.sh compose-file` puts the
#             reverse proxy on each application's network under ${INFRA_HOST} too; dev's doesn't
#   rewrite   review round 1 (2026-10-22): `networks.sh compose-file` in a scratch copy, with a fake
#             docker answering the labelled network c4-infra.faito: with the daemon answering but no
#             c4-infra network yet (a fresh host), it lists c4-infra.faito; a leftover
#             compose.apps.yml.new (a directory) doesn't stop it; and in a Linux container (bash:5.2,
#             which has flock), it waits while another process holds the lock on the stack's
#             directory, then writes the file
#
# covers: up.sh env.sh compose.yml compose.dev.yml caddy/ keycloak/ keycloak-import/ reverse-proxy/
# covers: certs/ register-app.sh registry.sh registry.txt routes.sh networks.sh
# covers: registration-account.sh tlds-alpha-by-domain.txt compose.demo.yml rabbitmq/
# covers: tests/fixtures/0003/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/keycloak.sh

RABBITMQ=c4-infra.rabbitmq
FAITO_DIR=${FAITO_DIR:-../faito}
SHARED='c4-infra.grafana-lgtm c4-infra.keycloak c4-infra.mailpit c4-infra.rabbitmq c4-infra.reverse-proxy'
STANDIN_IMAGE=caddy:2.11.4-alpine
STANDIN=tickee.network-standin

work=$(mktemp -d)
remove_tickee=false
cleanup() {
  docker rm -f "$STANDIN" > /dev/null 2>&1
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
  awk -F: -v port="$hex" '$2 == port { print $1 }' "$1" | LC_ALL=C sort -u | paste -sd' ' -
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
    | sed '/^$/d' | LC_ALL=C sort | paste -sd' ' -
}
networks_of() { # <container>: its networks, sorted, on one line
  docker inspect -f '{{range $name, $_ := .NetworkSettings.Networks}}{{$name}}{{"\n"}}{{end}}' "$1" 2> /dev/null \
    | tr -d '\r' | sed '/^$/d' | LC_ALL=C sort | paste -sd' ' -
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
    check "RQ-10: $port listens on the loopback only (${found:-not listening})" loopback_only "$found"
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
  local address
  docker network inspect c4-infra.tickee > /dev/null 2>&1 || remove_tickee=true
  register_tickee() { bash register-app.sh --app tickee > "$work/tickee.log" 2>&1 || { cat "$work/tickee.log"; return 1; }; }
  check "Tickee registers (bash register-app.sh --app tickee: its network only)" register_tickee
  check "c4-infra.tickee holds the five shared services, not keycloak-db" holds_shared c4-infra.tickee
  docker rm -f "$STANDIN" > /dev/null 2>&1
  start_standin() {
    docker run -d --name "$STANDIN" --network c4-infra.tickee "$STANDIN_IMAGE" \
      caddy respond --listen :7080 "$STANDIN" > /dev/null
  }
  check "Tickee's HTTP stand-in starts on c4-infra.tickee ($STANDIN, $STANDIN_IMAGE)" start_standin
  keycloak_reaches() { # 30 s at most, while the stand-in starts; the last attempt's error shown
    local deadline=$((SECONDS + 30)) error
    until error=$(MSYS_NO_PATHCONV=1 docker exec "$KC_CONTAINER" bash -c "exec 3<>/dev/tcp/$STANDIN/7080" \
      < /dev/null 2>&1); do
      [ "$SECONDS" -lt "$deadline" ] || { echo "no answer in 30 s: ${error:-none}"; return 1; }
      sleep 1
    done
  }
  check "AC-07: Keycloak reaches $STANDIN:7080, a container on Tickee's network" keycloak_reaches
  check "control: from c4-infra.tickee, $STANDIN:7080 answers" \
    docker run --rm --network c4-infra.tickee alpine:3 nc -z -w 3 "$STANDIN" 7080
  check "AC-07: from c4-infra.faito, $STANDIN:7080 can't be reached by name" \
    fails docker run --rm --network c4-infra.faito alpine:3 nc -z -w 3 "$STANDIN" 7080
  address=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$STANDIN" | tr -d '\r')
  check "$STANDIN has an address (${address:-none})" test -n "$address"
  check "AC-07: from c4-infra.faito, $address:7080 can't be reached" \
    fails docker run --rm --network c4-infra.faito alpine:3 nc -z -w 3 "$address" 7080
  docker rm -f "$STANDIN" > /dev/null 2>&1
  check "the stand-in is removed" test -z "$(docker ps -aq -f "name=^$STANDIN\$")"
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

# a path of this machine, as the docker CLI wants it (a Windows path under Git Bash)
host_path() { if command -v cygpath > /dev/null; then cygpath -w "$1"; else printf "%s" "$1"; fi; }

part_rewrite() {
  local scratch=$work/rewrite status
  mkdir -p "$scratch/stubs"
  cp networks.sh registry.sh registry.txt "$scratch/"
  printf 'INFRA_ENV=dev\n' > "$scratch/.env"
  # the daemon answers (STUB_C4_INFRA=1: the c4-infra network too); the applications' networks:
  # c4-infra.faito
  cat > "$scratch/stubs/docker" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  'info --format {{.ServerVersion}}') echo 29.0.0 ;;
  'network inspect c4-infra --format {{.Name}}') [ "${STUB_C4_INFRA:-0}" = 1 ] && echo c4-infra || exit 1 ;;
  'network ls --filter label=c4-infra.app'*) echo 'c4-infra.faito faito' ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$scratch/stubs/docker"
  lists_faito() { grep -qxF '    name: c4-infra.faito' "$scratch/compose.apps.yml" || { cat "$scratch/compose.apps.yml"; return 1; }; }

  rm -f "$scratch/compose.apps.yml"
  PATH="$scratch/stubs:$PATH" bash "$scratch/networks.sh" compose-file > "$work/rewrite.log" 2>&1
  check "a fresh host (no c4-infra network yet): compose-file exits 0" test $? -eq 0
  check "it lists c4-infra.faito" lists_faito

  rm -f "$scratch/compose.apps.yml"
  mkdir "$scratch/compose.apps.yml.new"
  STUB_C4_INFRA=1 PATH="$scratch/stubs:$PATH" bash "$scratch/networks.sh" compose-file > "$work/rewrite.log" 2>&1
  status=$?
  check "a leftover compose.apps.yml.new (a directory): compose-file exits 0 (exit $status)" test "$status" -eq 0
  check "it lists c4-infra.faito" lists_faito
  rmdir "$scratch/compose.apps.yml.new"

  # flock on the stack's directory, held 5 s by another process: a rewrite waits for it
  rm -f "$scratch/compose.apps.yml"
  MSYS_NO_PATHCONV=1 docker run --rm --user 1000 -e STUB_C4_INFRA=1 -v "$(host_path "$scratch"):/w" bash:5.2 bash -c '
    export PATH=/w/stubs:$PATH
    flock /w sleep 5 &
    sleep 1
    timeout 2 bash /w/networks.sh compose-file; echo "while held: exit $?"
    [ -f /w/compose.apps.yml ] && echo "while held: written" || echo "while held: not written"
    wait
    bash /w/networks.sh compose-file; echo "released: exit $?"' > "$work/flock.log" 2>&1
  check "while another process holds the lock, a rewrite waits (stopped by timeout 2 s: 124, busybox's 143)" \
    grep -qxE 'while held: exit (124|143)' "$work/flock.log"
  check "and writes nothing" grep -qx 'while held: not written' "$work/flock.log"
  check "once released, it writes the file (exit 0)" grep -qx 'released: exit 0' "$work/flock.log"
  check "listing c4-infra.faito" lists_faito
}

[ $# -gt 0 ] || set -- rabbitmq networks tickee guard rewrite
for part in "$@"; do
  case "$part" in
    rabbitmq | networks | tickee | guard | rewrite)
      echo "# $part"
      "part_$part"
      ;;
    *)
      echo "Unknown part: $part (rabbitmq, networks, tickee, guard or rewrite)" >&2
      exit 2
      ;;
  esac
done
finish
