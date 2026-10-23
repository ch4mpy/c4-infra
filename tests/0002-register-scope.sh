#!/usr/bin/env bash
# 0002: a registration touches only what the application's registry entry assigns to it (REQ-3,
# AC-3), on the workstation. register-app.sh runs with a fake docker (tests/lib/stubs.sh), which
# logs each call: as Faito, each of these is refused, saying why, before any docker call:
#
#   - Hurura'a's realm file (public-facing) with --reset-realms, and a realm file not named
#     <realm>-realm.json;
#   - Hurura'a's RabbitMQ user;
#   - a themes directory holding tickee (Tickee's theme): keycloak/themes/tickee is left as it was;
#   - a routes file serving hururaa.c4-soft.com, one routing to keycloak:8080.
#
# The checks pass for what the entry assigns: Faito's realm (imported as realm faito, whatever its
# file's "realm" field says) and its RabbitMQ user reach docker. And registry.sh check refuses an
# entry claiming Keycloak's master realm or RabbitMQ's administrator (plan, Deviations), which
# register-app.sh then refuses before any docker call.
#
#   bash tests/0002-register-scope.sh
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/stubs.sh

FIXTURES=tests/fixtures/0002
TICKEE_THEME=keycloak/themes/tickee

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
stub_path "$work/stubs" docker

# The fingerprint of Tickee's installed theme: "absent", or the cksum of its files
tickee_theme() {
  if [ -e "$TICKEE_THEME" ]; then
    (cd "$TICKEE_THEME" && find . -type f | LC_ALL=C sort | xargs -r cksum | cksum)
  else
    echo absent
  fi
}

# register-app.sh <option…> with the fake docker first in PATH; sets status, leaves its output in
# $work/out and the docker calls in $work/docker.log
register() {
  : > "$work/docker.log"
  RABBITMQ_PASSWORD=not-a-secret-0002 STUB_LOG="$work/docker.log" PATH="$work/stubs:$PATH" \
    bash ./register-app.sh "$@" > "$work/out" 2>&1 < /dev/null
  status=$?
}
refused() {
  [ "$status" -ne 0 ] || { echo "exited 0:"; cat "$work/out"; return 1; }
}
exited_0() {
  [ "$status" -eq 0 ] || { echo "exit $status:"; cat "$work/out"; return 1; }
}
says() { # <text>
  grep -qF -- "$1" "$work/out" || { echo "output:"; cat "$work/out"; return 1; }
}
no_docker_call() {
  [ ! -s "$work/docker.log" ] || { echo "docker called:"; head -n 5 "$work/docker.log"; return 1; }
}
docker_called() { # <text>: a docker call holds it
  grep -qF -- "$1" "$work/docker.log" || { echo "docker calls:"; cat "$work/docker.log"; return 1; }
}
refused_before_docker() { # <label> <text the refusal holds>
  check "$1: refused" refused
  check "$1: says \"$2\"" says "$2"
  check "$1: nothing was registered" says "nothing was registered"
  check "$1: before any docker call" no_docker_call
}

# Hurura'a's realm, with --reset-realms: neither deleted nor imported
register --app faito --realm "$FIXTURES/public-facing-realm.json" --reset-realms
refused_before_docker "Hurura'a's realm file, --reset-realms" "realm public-facing is not faito's"
register --app faito --realm "$FIXTURES/faito-realm-named-public-facing.json"
refused_before_docker "a realm file not named <realm>-realm.json" "a realm export is named <realm>-realm.json"

# Hurura'a's RabbitMQ user
register --app faito --rabbitmq-user hururaa-api --rabbitmq-password-env RABBITMQ_PASSWORD
refused_before_docker "Hurura'a's RabbitMQ user" "--rabbitmq-user hururaa-api: not faito's RabbitMQ user"

# Tickee's theme
before=$(tickee_theme)
register --app faito --themes "$FIXTURES/themes"
refused_before_docker "a themes directory holding tickee" "theme tickee is not faito's"
check "Tickee's installed theme is as it was ($before)" test "$(tickee_theme)" = "$before"

# Server blocks for another host, or to a shared service's port
register --app faito --proxy "$FIXTURES/routes-hururaa-host.routes"
refused_before_docker "a routes file serving hururaa.c4-soft.com" "routes name neither a host nor a port: 'https://hururaa.c4-soft.com/*'"
register --app faito --proxy "$FIXTURES/routes-keycloak-port.routes"
refused_before_docker "a routes file routing to keycloak:8080" "routes name neither a host nor a port: 'keycloak:8080'"

# What the entry assigns passes the checks: docker is called. A realm file named after Faito's realm
# whose "realm" field says public-facing is imported as realm faito.
cp "$FIXTURES/faito-realm-named-public-facing.json" "$work/faito-realm.json"
register --app faito --realm "$work/faito-realm.json" --reset-realms
check "Faito's realm file passes the checks (exit 0)" exited_0
check "it is imported" says "Importing realm faito"
check "under the name of its file (-s realm=faito)" docker_called "create realms -f - -s realm=faito"
register --app faito --rabbitmq-user faito-api --rabbitmq-password-env RABBITMQ_PASSWORD
check "Faito's RabbitMQ user passes the checks (exit 0)" exited_0
check "it reaches RabbitMQ" docker_called "exec -i c4-infra.rabbitmq"

# Deviation: no entry may claim Keycloak's master realm or RabbitMQ's administrator
registry_refuses() { # <fixture> <text>
  REGISTRY_FILE="$PWD/$FIXTURES/$1" bash registry.sh check > "$work/out" 2>&1
  status=$?
  check "$1: registry.sh check refuses it" refused
  check "$1: says \"$2\"" says "$2"
}
registry_refuses registry-master-realm.txt "registry-master-realm.txt:6: realm master is Keycloak's own"
registry_refuses registry-rabbitmq-admin.txt "registry-rabbitmq-admin.txt:6: RabbitMQ user admin is the broker's administrator"
REGISTRY_FILE="$PWD/$FIXTURES/registry-master-realm.txt" register --app verif-master --realm "$work/faito-realm.json"
check "with it, register-app.sh refuses verif-master" refused
check "saying the registry is invalid" says "The registry is invalid"
check "before any docker call" no_docker_call
REGISTRY_FILE="$PWD/$FIXTURES/registry-rabbitmq-admin.txt" register --app verif-admin \
  --rabbitmq-user admin --rabbitmq-password-env RABBITMQ_PASSWORD
check "with it, register-app.sh refuses verif-admin" refused
check "saying the registry is invalid" says "The registry is invalid"
check "before any docker call" no_docker_call

# Review round 1 (2026-10-22): nor a theme built into Keycloak (base, keycloak), which a theme
# directory of that name would replace for every realm
registry_refuses registry-builtin-theme.txt "registry-builtin-theme.txt:6: theme keycloak is built into Keycloak"
registry_refuses registry-builtin-theme.txt "registry-builtin-theme.txt:7: theme base is built into Keycloak"
mkdir -p "$work/themes/keycloak/login"
echo 'parent=base' > "$work/themes/keycloak/login/theme.properties"
REGISTRY_FILE="$PWD/$FIXTURES/registry-builtin-theme.txt" register --app verif-theme --themes "$work/themes"
check "with it, register-app.sh refuses verif-theme" refused
check "saying the registry is invalid" says "The registry is invalid"
check "before any docker call" no_docker_call

finish
