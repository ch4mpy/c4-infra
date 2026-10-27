#!/usr/bin/env bash
# 0012: the behaviours the master realm's one-shot import relies on (RQ-06), checked in throwaway
# containers of the stack's image (a file database on a throwaway volume, no published port, the
# values in an --env-file of a temporary directory):
#
#   (a) the import compose.yml gives keycloak-import (`import --dir … --override false`, here on a
#       file database: kc_import_args) creates, on an empty database, the master realm from
#       keycloak-import/master-realm.json, its ${VAR} taken from the environment: a Keycloak started
#       on that database serves it, its administrator logs in with the admin CLI, and its SMTP host
#       is the environment's;
#   (b) run again with another SMTP host, the import changes nothing: the master realm keeps the
#       first one;
#   (c) docker compose up -d --wait succeeds when a service depends on a one-shot that completed
#       (service_completed_successfully), and the one-shot isn't left running.
#
#   bash tests/0012-import-facts.sh
#
# Needs the image c4-infra/keycloak (up.sh builds it) and caddy:2.11.4-alpine (the stack's). The
# throwaway containers, volume and compose project are removed whatever happens.
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/keycloak.sh

IMAGE=c4-infra/keycloak
PREFIX=c4-infra.0012-facts
VOLUME=c4-infra-0012-facts-data
PROJECT=c4-infra-0012-facts
SERVER=http://localhost:8080/auth
KCADM=/opt/keycloak/bin/kcadm.sh
export MSYS_NO_PATHCONV=1

host_path() {
  if command -v cygpath > /dev/null; then cygpath -w "$1"; else printf '%s' "$1"; fi
}

umask 077
work=$(mktemp -d)
remove_throwaways() {
  docker rm -f $(docker ps -aq -f "name=^$PREFIX-") > /dev/null 2>&1
  docker volume rm -f "$VOLUME" > /dev/null 2>&1
}
cleanup() {
  remove_throwaways
  [ ! -f "$work/compose.yml" ] || docker compose -p "$PROJECT" -f "$(host_path "$work/compose.yml")" down -v > /dev/null 2>&1
  rm -rf "$work"
}
trap cleanup EXIT
remove_throwaways
import_args=$(kc_import_args)
check "keycloak-import's command is read from the dev model (${import_args//$'\n'/ })" test -n "$import_args"
mapfile -t IMPORT_ARGS <<< "$import_args"

KC_CLI_PASSWORD=$(openssl rand -hex 16)
export KC_CLI_PASSWORD

# The variables master-realm.json names, as the stack's .env and compose files give them
import_env() { # <file> <smtp host>
  printf '%s\n' C4_MASTER_ADMIN_USERNAME=admin "C4_MASTER_ADMIN_PASSWORD=$KC_CLI_PASSWORD" \
    INFRA_HOST=host.docker.internal MAILPIT_SMTP_USER=mailpit "MAILPIT_SMTP_PASSWORD=$(openssl rand -hex 8)" \
    "C4_MASTER_SMTP_HOST=$2" C4_MASTER_SMTP_STARTTLS=true C4_MASTER_RESET_PASSWORD_ALLOWED=true > "$1"
}
# <log> <env file>: the one-shot import on the throwaway volume, its output in $work/<log>, shown
# when it fails
import_once() {
  docker run --rm --name "$PREFIX-import" --env-file "$(host_path "$2")" \
    -v "$VOLUME:/opt/keycloak/data" -v "$(host_path "$PWD/keycloak-import"):/opt/keycloak/data/import:ro" \
    "$IMAGE" "${IMPORT_ARGS[@]}" > "$work/$1" 2>&1 < /dev/null || { tail -n 10 "$work/$1"; return 1; }
}
# A Keycloak on that volume, with no import and none of the import's variables
serve() {
  docker run -d --name "$PREFIX-serve" -v "$VOLUME:/opt/keycloak/data" "$IMAGE" start-dev --db=dev-file > /dev/null
}
ready() { kc_throwaway_ready "$PREFIX-serve"; }
# stopped, its file database closed (a killed Keycloak loses its last writes there)
stop_serving() {
  docker stop -t 60 "$PREFIX-serve" > /dev/null 2>&1
  docker rm "$PREFIX-serve" > /dev/null 2>&1
}
admin() { # <kcadm args…>: the import's administrator, with the admin CLI
  docker exec -e KC_CLI_PASSWORD "$PREFIX-serve" "$KCADM" "$@" \
    --no-config --server "$SERVER" --realm master --user admin < /dev/null
}
smtp_host_is() { # <host>
  local value
  value=$(admin get realms/master 2> /dev/null | jq -r '.smtpServer.host') || { echo "get realms/master failed"; return 1; }
  [ "$value" = "$1" ] || { echo "smtpServer.host is $value, not $1"; return 1; }
}
exited_0() { # <log>
  [ "$status" -eq 0 ] || { echo "exit $status:"; tail -n 10 "$work/$1"; return 1; }
}
says() { # <log> <text>
  grep -qF -- "$2" "$work/$1" || { echo "output:"; tail -n 10 "$work/$1"; return 1; }
}

# (a)
docker volume create "$VOLUME" > /dev/null
import_env "$work/first.env" first-smtp-host
check "(a) the one-shot import on an empty database exits 0 (${IMPORT_ARGS[*]})" import_once first.log "$work/first.env"
check "(a) it imports the master realm" says first.log "Realm 'master' imported"
serve
check "(a) a Keycloak started on that database is ready" ready
check "(a) the import's administrator logs in with the admin CLI" admin get realms/master --fields realm
check "(a) the master realm's SMTP host is the environment's" smtp_host_is first-smtp-host
stop_serving

# (b)
import_env "$work/second.env" second-smtp-host
check "(b) the import run again exits 0" import_once second.log "$work/second.env"
serve
check "(b) Keycloak is ready again" ready
check "(b) the master realm keeps the first SMTP host" smtp_host_is first-smtp-host
stop_serving

# (c)
cat > "$work/compose.yml" <<'YAML'
services:
  once:
    image: caddy:2.11.4-alpine
    command: ["sh", "-c", "exit 0"]
    restart: "no"
  service:
    image: caddy:2.11.4-alpine
    command: ["caddy", "respond", "--listen", ":8080", "ok"]
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8080/"]
      interval: 1s
      retries: 30
    depends_on:
      once:
        condition: service_completed_successfully
YAML
docker compose -p "$PROJECT" -f "$(host_path "$work/compose.yml")" up -d --wait > "$work/up.log" 2>&1
status=$?
check "(c) docker compose up -d --wait exits 0 with a completed one-shot dependency ($(docker compose version --short))" exited_0 up.log
once_exited() {
  local state
  state=$(docker compose -p "$PROJECT" -f "$(host_path "$work/compose.yml")" ps -a --format '{{.Service}} {{.State}}' | tr -d '\r' | grep '^once ')
  [ "$state" = "once exited" ] || { echo "once: ${state:-absent}"; return 1; }
}
check "(c) the one-shot isn't left running" once_exited
docker compose -p "$PROJECT" -f "$(host_path "$work/compose.yml")" up -d --wait > "$work/up-again.log" 2>&1
status=$?
check "(c) a second up -d --wait exits 0 too (the one-shot runs again)" exited_0 up-again.log

finish
