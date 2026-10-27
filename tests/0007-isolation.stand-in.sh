#!/usr/bin/env bash
# 0007: on a stand-in demo host, an application's containers reach their own network's containers
# and the shared services they use, and nothing else (AC-01 to AC-04, AC-09, AC-10):
#
#   - the accounts and the shared stack as docs/demo-setup.md prepares them (stand_in_accounts
#     faito hururaa: deployed as c4-infra over ssh, demo/deploy.sh); the probe image
#     (tests/fixtures/0007/probe/: an echo on :7080, curl, nmap, nc) built in the stand-in's daemon;
#   - Hurura'a, then Faito (tests/fixtures/0007/<app>/: a gateway on the external network
#     c4-infra.<app>), each rsynced to ~<app>/<app>/ with its own key, registered (sudo c4-app
#     register --proxy <app>.routes --rabbitmq-user <app>-api --rabbitmq-password-env
#     RABBITMQ_PASSWORD) and started (sudo c4-app up; no pull: the probe is local);
#   - AC-10: c4-infra.faito holds faito.gateway and the five shared services, not keycloak-db;
#     c4-infra.keycloak-db holds Keycloak and its database only, which is on no other network;
#     c4-infra.hururaa is the same before and after Faito's registration;
#   - from faito.gateway: AC-01, neither hururaa.gateway nor keycloak-db, by name or by address;
#     AC-02, Mailpit's API answers 401; AC-03, Keycloak, SMTP with Mailpit's credentials, AMQP, OTLP
#     and the shared host's name (Caddy's address on c4-infra.faito) answer, and Keycloak and Caddy
#     reach faito.gateway; AC-09, nmap finds open on each shared service exactly the ports of RQ-02,
#     RQ-04 and RQ-06;
#   - AC-04: the shared stack recreated as c4-infra (docker compose up -d --force-recreate --wait),
#     AC-03's reachability again, without registering anything.
#
#   bash tests/0007-isolation.stand-in.sh      (bash tests/run.sh --all runs it)
#
# As tests/0002-accounts.stand-in.sh: the Keycloak image is the one up.sh builds here, loaded into
# the stand-in; Let's Encrypt is kept out (tests/stand-in-host/compose.no-acme.yml). The
# applications' .env (RABBITMQ_PASSWORD, random) is written here into the copy each one uploads
# (.gitignore ignores every .env). Passwords travel on stdin, never on a command line.
#
# covers: demo/ compose.yml compose.demo.yml register-app.sh registry.sh registry.txt routes.sh
# covers: networks.sh registration-account.sh tlds-alpha-by-domain.txt rabbitmq/
# covers: tests/fixtures/0007/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/stand-in-host.sh

FIXTURES=tests/fixtures/0007
STACK=/home/c4-infra/c4-infra
UPLOADS=/root/apps-0007
PROBE=c4-test/probe
SHARED=(reverse-proxy keycloak mailpit rabbitmq grafana-lgtm)
# AC-09: the ports that answer on each shared service, from an application's network (RQ-02, RQ-04,
# RQ-06; RabbitMQ's 4369 and 25672, its 15672 and Grafana LGTM's 7946, 9095-9097 and 13133 not)
declare -A OPEN=(
  [keycloak]='8080 9000'
  [mailpit]='1025 8025'
  [rabbitmq]='5672 15692'
  [grafana-lgtm]='3000 3100 3200 4040 4317 4318 9090'
  [reverse-proxy]='80 443'
)

umask 077
work=$(mktemp -d)
trap 'stand_in_down; rm -rf "$work"' EXIT

# <log> <account> <command>: over ssh as <account>, its output into $work/<log>, its exit status
# into $status
as() {
  local log=$1
  stand_in_ssh "$2" "$3" > "$work/$log" 2>&1
  status=$?
}
exited_0() { # <log>
  [ "$status" -eq 0 ] || { echo "exit $status:"; tail -n 25 "$work/$1"; return 1; }
}
running() { # <container>
  [ "$(stand_in_exec docker inspect -f '{{.State.Running}}' "$1" 2> /dev/null | tr -d '\r')" = true ] \
    || { echo "$1 doesn't run"; return 1; }
}
# <container> <command…>: the command in that container of the stand-in, stdin closed
in_container() {
  local container=$1
  shift
  stand_in_exec docker exec "$container" "$@" < /dev/null
}
from_faito() { in_container faito.gateway "$@"; }

# An application's fixture into $UPLOADS/<app>, its .env written here (a random RabbitMQ password),
# then rsynced to ~<app>/<app>/ with its own key
upload() { # <app>
  local app=$1
  stand_in_exec rm -rf "$UPLOADS/$app"
  stand_in_exec mkdir -p "$UPLOADS/$app" || return 1
  (cd "$FIXTURES/$app" && tar -cf - .) | stand_in_exec -i tar -xf - --no-same-owner -C "$UPLOADS/$app" || return 1
  printf 'RABBITMQ_PASSWORD=%s\n' "$(openssl rand -hex 16)" \
    | stand_in_exec -i sh -c 'umask 077 && cat > "$1"' sh "$UPLOADS/$app/.env" || return 1
  stand_in_exec bash -c 'cd "$1" && rsync -az --delete -e "$2" ./ "$3@127.0.0.1:~/$3/"' \
    sh "$UPLOADS/$app" "$(stand_in_ssh_command "$app")" "$app"
}

# The containers of a network, by name, sorted, on one line ("none" when it doesn't exist)
network_containers() { # <network>
  stand_in_exec docker network inspect "$1" > /dev/null 2>&1 || { echo none; return 0; }
  stand_in_exec docker network inspect -f '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}' "$1" \
    | tr -d '\r' | sed '/^$/d' | sort | paste -sd' ' -
}
network_exists() { # <network>
  stand_in_exec docker network inspect "$1" > /dev/null 2>&1 || { echo "no network $1"; return 1; }
}
containers_are() { # <network> <expected, sorted, space-separated>
  local found
  found=$(network_containers "$1")
  [ "$found" = "$2" ] || { echo "$1 holds: ${found:-nothing}"; return 1; }
}
networks_of() { # <container>: its networks, sorted, on one line
  stand_in_exec docker inspect -f '{{range $name, $_ := .NetworkSettings.Networks}}{{$name}}{{"\n"}}{{end}}' "$1" 2> /dev/null \
    | tr -d '\r' | sed '/^$/d' | sort | paste -sd' ' -
}
addresses_of() { # <container>: its addresses on every network, one per line
  stand_in_exec docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{"\n"}}{{end}}' "$1" 2> /dev/null \
    | tr -d '\r' | sed '/^$/d'
}
address_on() { # <container> <network>
  stand_in_exec docker inspect -f "{{with index .NetworkSettings.Networks \"$2\"}}{{.IPAddress}}{{end}}" "$1" 2> /dev/null \
    | tr -d '\r'
}

# AC-01: from faito.gateway (running), nc doesn't connect
unreachable() { # <host or address> <port>
  running faito.gateway || return 1
  if from_faito nc -z -w 3 "$1" "$2" > /dev/null 2>&1; then
    echo "faito.gateway connects to $1:$2"
    return 1
  fi
}
reachable() { # <host or address> <port>
  running faito.gateway || return 1
  from_faito nc -z -w 3 "$1" "$2"
}
# curl from faito.gateway: the status code is <code>
answers() { # <code> <curl argument…>
  local code=$1 found
  shift
  running faito.gateway || return 1
  found=$(from_faito curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$@" | tr -d '\r')
  [ "$found" = "$code" ] || { echo "status ${found:-none}"; return 1; }
}
# the shared host's name, from faito.gateway, resolves to Caddy's address on c4-infra.faito
issuer_is_caddy() {
  local resolved caddy
  running faito.gateway || return 1
  resolved=$(from_faito getent hosts infra.c4-soft.com | awk '{ print $1 }' | tr -d '\r' | paste -sd' ' -)
  caddy=$(address_on c4-infra.reverse-proxy c4-infra.faito)
  [ -n "$caddy" ] && [ "$resolved" = "$caddy" ] \
    || { echo "infra.c4-soft.com resolves to '${resolved:-nothing}', Caddy's address on c4-infra.faito is '${caddy:-none}'"; return 1; }
}
# SMTP with Mailpit's credentials (the stack's .env, read in the stand-in): a netrc file written in
# faito.gateway through stdin (printf is a builtin: no password on a command line)
smtp_sends() {
  running faito.gateway || return 1
  stand_in_exec bash -c '
    value() { local line; line=$(grep -m1 "^$1=" "$2/.env"); line=${line#*=}; printf "%s" "${line//\$\$/\$}"; }
    printf "machine mailpit login %s password %s\n" "$(value MAILPIT_SMTP_USER "$1")" "$(value MAILPIT_SMTP_PASSWORD "$1")" \
      | docker exec -i faito.gateway sh -c "umask 077 && cat > /tmp/netrc"' sh "$STACK" || return 1
  printf 'From: faito@faito.c4-soft.com\r\nTo: visitor@example.org\r\nSubject: 0007\r\n\r\nAC-3\r\n' \
    | stand_in_exec -i docker exec -i faito.gateway sh -c 'cat > /tmp/mail.txt' || return 1
  from_faito curl -s --max-time 10 smtp://mailpit:1025 --netrc-file /tmp/netrc \
    --mail-from faito@faito.c4-soft.com --mail-rcpt visitor@example.org --upload-file /tmp/mail.txt
}
keycloak_reaches_gateway() {
  in_container c4-infra.keycloak bash -c 'exec 3<>/dev/tcp/faito.gateway/7080'
}
caddy_reaches_gateway() {
  local body
  body=$(in_container c4-infra.reverse-proxy wget -qO- http://faito.gateway:7080/ | tr -d '\r')
  [ "$body" = faito.gateway ] || { echo "answer: ${body:-none}"; return 1; }
}
# AC-09: the TCP ports nmap finds open on <host> from faito.gateway, sorted, on one line
open_ports() { # <host>
  from_faito nmap -Pn -p- --open -T4 -oG - "$1" | tr -d '\r' | sed -n 's/.*Ports: //p' | tr ',' '\n' \
    | sed -n 's|^[[:space:]]*\([0-9][0-9]*\)/open/.*|\1|p' | sort -n | paste -sd' ' -
}
open_ports_are() { # <host> <expected>
  local found
  running faito.gateway || return 1
  found=$(open_ports "$1")
  [ "$found" = "$2" ] || { echo "open on $1: ${found:-none}"; return 1; }
}

ac3_reachability() { # <label prefix>
  local label=$1
  check "$label: http://keycloak:8080/auth/realms/master answers 200" answers 200 http://keycloak:8080/auth/realms/master
  check "$label: SMTP with Mailpit's credentials (smtp://mailpit:1025)" smtp_sends
  check "$label: RabbitMQ's AMQP (rabbitmq:5672)" reachable rabbitmq 5672
  check "$label: Grafana LGTM's OTLP receiver (POST http://grafana-lgtm:4318/v1/traces) answers 200" \
    answers 200 -X POST -H 'Content-Type: application/json' -d '{}' http://grafana-lgtm:4318/v1/traces
  check "$label: infra.c4-soft.com resolves to Caddy's address on c4-infra.faito" issuer_is_caddy
  check "$label: infra.c4-soft.com:443 answers" reachable infra.c4-soft.com 443
  check "$label: Keycloak reaches faito.gateway:7080 (back-channel logout)" keycloak_reaches_gateway
  check "$label: Caddy reaches http://faito.gateway:7080/" caddy_reaches_gateway
}

check "the stand-in host starts" stand_in_up
check "the accounts (c4-infra, hururaa, faito), the shared stack deployed as c4-infra" stand_in_accounts hururaa faito
build_probe() {
  (cd "$FIXTURES/probe" && tar -cf - .) | stand_in_exec -i docker build -q -t "$PROBE" - > /dev/null
}
check "the probe image is built in the stand-in ($PROBE)" build_probe

# Hurura'a, then Faito: uploaded, registered, started; the ups' outcomes are checked after AC-10's
# first assertion (without a network of its own, an application doesn't start)
check "Hurura'a's files are rsynced to ~hururaa/hururaa/ with its key" upload hururaa
as hururaa-register.log hururaa "sudo c4-app register --proxy hururaa.routes --rabbitmq-user hururaa-api --rabbitmq-password-env RABBITMQ_PASSWORD"
check "Hurura'a registers" exited_0 hururaa-register.log
as hururaa-up.log hururaa "sudo c4-app up"
hururaa_up=$status
hururaa_before=$(network_containers c4-infra.hururaa)
check "Faito's files are rsynced to ~faito/faito/ with its key" upload faito
as faito-register.log faito "sudo c4-app register --proxy faito.routes --rabbitmq-user faito-api --rabbitmq-password-env RABBITMQ_PASSWORD"
check "Faito registers" exited_0 faito-register.log
as faito-up.log faito "sudo c4-app up"
faito_up=$status

# AC-10
check "AC-10: Faito's registration created its network c4-infra.faito" network_exists c4-infra.faito
status=$hururaa_up
check "Hurura'a starts (sudo c4-app up)" exited_0 hururaa-up.log
status=$faito_up
check "Faito starts (sudo c4-app up)" exited_0 faito-up.log
check "faito.gateway runs" running faito.gateway
check "hururaa.gateway runs" running hururaa.gateway
check "AC-10: c4-infra.faito holds faito.gateway and the five shared services, not keycloak-db" containers_are c4-infra.faito \
  'c4-infra.grafana-lgtm c4-infra.keycloak c4-infra.mailpit c4-infra.rabbitmq c4-infra.reverse-proxy faito.gateway'
check "AC-10: c4-infra.keycloak-db holds Keycloak and its database only" containers_are c4-infra.keycloak-db \
  'c4-infra.keycloak c4-infra.keycloak-db'
keycloak_db_networks=$(networks_of c4-infra.keycloak-db)
check "AC-10: keycloak-db is on no other network (${keycloak_db_networks:-none})" test "$keycloak_db_networks" = c4-infra.keycloak-db
check "AC-10: c4-infra.hururaa held hururaa.gateway and the five shared services before Faito's registration" \
  test "$hururaa_before" = 'c4-infra.grafana-lgtm c4-infra.keycloak c4-infra.mailpit c4-infra.rabbitmq c4-infra.reverse-proxy hururaa.gateway'
check "AC-10: and is unchanged after it" containers_are c4-infra.hururaa "$hururaa_before"

# AC-01, from faito.gateway: by name, then by every address
check "AC-01: hururaa.gateway:7080 can't be reached by name" unreachable hururaa.gateway 7080
check "AC-01: keycloak-db:5432 can't be reached by name" unreachable keycloak-db 5432
hururaa_addresses=$(addresses_of hururaa.gateway)
check "hururaa.gateway has an address ($(paste -sd' ' - <<< "$hururaa_addresses"))" test -n "$hururaa_addresses"
for address in $hururaa_addresses; do
  check "AC-01: hururaa.gateway can't be reached at $address:7080" unreachable "$address" 7080
done
keycloak_db_addresses=$(addresses_of c4-infra.keycloak-db)
check "keycloak-db has an address ($(paste -sd' ' - <<< "$keycloak_db_addresses"))" test -n "$keycloak_db_addresses"
for address in $keycloak_db_addresses; do
  check "AC-01: keycloak-db can't be reached at $address:5432" unreachable "$address" 5432
done

# AC-02, a Faito container's part (Caddy's: tests/0003-demo-edge.sh)
check "AC-02: http://mailpit:8025/mailpit/api/v1/messages without credentials answers 401" \
  answers 401 http://mailpit:8025/mailpit/api/v1/messages

# AC-03
ac3_reachability "AC-03"

# AC-09
for service in "${SHARED[@]}"; do
  check "AC-09: open on $service: exactly ${OPEN[$service]}" open_ports_are "$service" "${OPEN[$service]}"
done

# AC-04: a deployment recreating the shared stack, nothing registered again
as recreate.log c4-infra "cd ~/c4-infra && docker compose up -d --force-recreate --wait --wait-timeout 300 < /dev/null"
check "AC-04: as c4-infra, docker compose up -d --force-recreate --wait exits 0" exited_0 recreate.log
ac3_reachability "AC-04, after the recreation"
check "AC-04: c4-infra.faito still holds faito.gateway and the five shared services" containers_are c4-infra.faito \
  'c4-infra.grafana-lgtm c4-infra.keycloak c4-infra.mailpit c4-infra.rabbitmq c4-infra.reverse-proxy faito.gateway'
check "AC-04: hururaa.gateway still can't be reached" unreachable hururaa.gateway 7080
finish
