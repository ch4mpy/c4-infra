#!/usr/bin/env bash
# 0002: a registration touches only what the application's registry entry assigns to it (RQ-03,
# AC-03), on the workstation. register-app.sh runs with a fake docker (tests/lib/stubs.sh), which
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
#
# covers: register-app.sh registry.sh registry.txt routes.sh networks.sh registration-account.sh
# covers: tlds-alpha-by-domain.txt keycloak/ tests/fixtures/0002/
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

# Review round 1 (2026-10-22): the .env reader the scripts share (registry.sh's dotenv_value) reads
# a value as compose does: "$$" is "$" (outside single quotes), " #" starts a comment in an unquoted
# value, quotes are removed, the last definition wins; what compose would interpolate is refused
# rather than read otherwise
dotenv() { # <key>: dotenv_value of $work/dotenv.env, its output in $work/out, its status in $status
  (source ./registry.sh && dotenv_value "$work/dotenv.env" "$1") > "$work/out" 2>&1
  status=$?
}
reads() { # <key> <value>
  dotenv "$1"
  [ "$status" -eq 0 ] && [ "$(cat "$work/out")" = "$2" ] || { echo "exit $status: [$(cat "$work/out")]"; return 1; }
}
cat > "$work/dotenv.env" <<'EOF'
DOLLARS=ab$$cd
COMMENT=ab$$cd # a comment
HASH=ab#cd
DOUBLE="a b # $$c"
SINGLE='x$$y # z'
SPACED = lead
export EXPORTED=v
TWICE=first
TWICE=last
CR=crlf
INTERPOLATED=pre${DOLLARS}post
EOF
sed -i 's/^CR=crlf$/CR=crlf\r/' "$work/dotenv.env"
check "dotenv_value: ab\$\$cd is ab\$cd" reads DOLLARS 'ab$cd'
check "dotenv_value: an unquoted value ends at ' #'" reads COMMENT 'ab$cd'
check "dotenv_value: a '#' without a space before it is the value's" reads HASH 'ab#cd'
check "dotenv_value: double quotes removed, \$\$ is \$ inside" reads DOUBLE 'a b # $c'
check "dotenv_value: single quotes keep \$\$" reads SINGLE 'x$$y # z'
check "dotenv_value: spaces around '=' and at the end" reads SPACED lead
check "dotenv_value: export KEY=" reads EXPORTED v
check "dotenv_value: the last definition wins" reads TWICE last
check "dotenv_value: a Windows line end" reads CR crlf
check "dotenv_value: a missing key is empty" reads MISSING ''
dotenv INTERPOLATED
check "dotenv_value: an interpolation is refused" refused
check "dotenv_value: saying compose would interpolate it" says "compose interpolates"

# Review round 3 (2026-10-23): a value of .env the reader refuses stops the script that reads it,
# rather than letting it go on with an empty value (finding 11: dotenv_value's status was lost in a
# [ … ] argument, a prefix assignment and a function's argument). Each script runs from a scratch copy
# of the stack, with its own .env and a fake docker that answers as a running daemon and logs each
# call. On the demo host, a refused INFRA_ENV took the reverse proxy's INFRA_HOST alias out of
# compose.apps.yml (networks.sh compose-file) and out of the attachment to a new network (ensure).
stack=$work/stack
mkdir -p "$stack" "$work/fake"
cp registry.sh routes.sh networks.sh register-app.sh registration-account.sh registry.txt tlds-alpha-by-domain.txt "$stack/"
cat > "$work/fake/docker" <<'EOF'
#!/usr/bin/env bash
# A running daemon: c4-infra.faito labelled, but missing until created; the shared services running,
# on none of its networks; the registration account's login refused with FAKE_ACCOUNT_LOGIN=fails
echo "docker $*" >> "${STUB_LOG:?}"
case " $* " in
  *" info "*) echo 29.0.0 ;;
  *" network ls "*) echo "c4-infra.faito faito" ;;
  *" network inspect "*) exit 1 ;;
  *State.Running*) echo true ;;
  *" --client "*)
    # as kcadm 26.8.1 says it (intent 0024)
    [ "${FAKE_ACCOUNT_LOGIN:-}" != fails ] || { echo "Invalid client or Invalid client credentials [unauthorized_client]" >&2; exit 1; } ;;
esac
exit 0
EOF
chmod +x "$work/fake/docker"
stack_run() { # <script> <arg…>: in the scratch stack, the fake docker first in PATH; as register()
  : > "$work/docker.log"
  STUB_LOG="$work/docker.log" PATH="$work/fake:$PATH" bash "$stack/$1" "${@:2}" > "$work/out" 2>&1 < /dev/null
  status=$?
}
no_docker_call_holds() { # <text>
  ! grep -qF -- "$1" "$work/docker.log" || { echo "docker calls:"; cat "$work/docker.log"; return 1; }
}
apps_file_holds() { # <line>
  grep -qxF -- "$1" "$stack/compose.apps.yml" || { echo "compose.apps.yml:"; cat "$stack/compose.apps.yml"; return 1; }
}
apps_file_is() { # <content>
  [ "$(cat "$stack/compose.apps.yml")" = "$1" ] || { echo "compose.apps.yml:"; cat "$stack/compose.apps.yml"; return 1; }
}
before_apps="# the scratch stack's compose.apps.yml, before the run"

# networks.sh: what the demo host must keep (must not fire), then INFRA_ENV and INFRA_HOST refused
printf '%s\n' INFRA_ENV=demo INFRA_HOST=infra.c4-soft.com > "$stack/.env"
stack_run networks.sh compose-file
check "networks.sh compose-file, a valid demo .env: exits 0" exited_0
check "networks.sh compose-file, a valid demo .env: the reverse proxy keeps the INFRA_HOST alias" \
  apps_file_holds "        aliases: ['\${INFRA_HOST}']"
stack_run networks.sh ensure faito
check "networks.sh ensure, a valid demo .env: exits 0" exited_0
check "networks.sh ensure, a valid demo .env: attaches the reverse proxy as INFRA_HOST" \
  docker_called "network connect --alias reverse-proxy --alias infra.c4-soft.com c4-infra.faito c4-infra.reverse-proxy"

printf '%s\n' 'INFRA_ENV=${INFRA_ENV:-demo}' INFRA_HOST=infra.c4-soft.com > "$stack/.env"
printf '%s\n' "$before_apps" > "$stack/compose.apps.yml"
stack_run networks.sh compose-file
check "networks.sh compose-file, INFRA_ENV refused: stops" refused
check "networks.sh compose-file, INFRA_ENV refused: says so" says "INFRA_ENV of $stack/.env is refused"
check "networks.sh compose-file, INFRA_ENV refused: compose.apps.yml left as it was" apps_file_is "$before_apps"
stack_run networks.sh ensure faito
check "networks.sh ensure, INFRA_ENV refused: stops" refused
check "networks.sh ensure, INFRA_ENV refused: says so" says "INFRA_ENV of $stack/.env is refused"
check "networks.sh ensure, INFRA_ENV refused: no network created" no_docker_call_holds "network create"
check "networks.sh ensure, INFRA_ENV refused: no service attached" no_docker_call_holds "network connect"
check "networks.sh ensure, INFRA_ENV refused: compose.apps.yml left as it was" apps_file_is "$before_apps"

printf '%s\n' INFRA_ENV=demo "INFRA_HOST='infra.c4-soft.com" > "$stack/.env"
stack_run networks.sh ensure faito
check "networks.sh ensure, INFRA_HOST refused: stops" refused
check "networks.sh ensure, INFRA_HOST refused: says so" says "INFRA_HOST of $stack/.env is refused"
check "networks.sh ensure, INFRA_HOST refused: no network created" no_docker_call_holds "network create"

# register-app.sh: INFRA_ENV, and the registration account's secret (a prefix assignment), refused
cat > "$stack/.env" <<'EOF'
INFRA_ENV=${INFRA_ENV}
KC_REGISTRATION_CLIENT_ID=c4-registration
KC_REGISTRATION_CLIENT_SECRET=0123abcd
EOF
stack_run register-app.sh --app faito --realm "$work/faito-realm.json"
check "register-app.sh, INFRA_ENV refused: stops" refused
check "register-app.sh, INFRA_ENV refused: says so" says "INFRA_ENV of $stack/.env is refused"
check "register-app.sh, INFRA_ENV refused: before any docker call" no_docker_call
cat > "$stack/.env" <<'EOF'
INFRA_ENV=dev
KC_REGISTRATION_CLIENT_ID=c4-registration
KC_REGISTRATION_CLIENT_SECRET="0123\abcd"
EOF
stack_run register-app.sh --app faito --realm "$work/faito-realm.json"
check "register-app.sh, the registration secret refused: stops" refused
check "register-app.sh, the registration secret refused: says so" \
  says "KC_REGISTRATION_CLIENT_SECRET of $stack/.env is refused"
check "register-app.sh, the registration secret refused: no login with an empty secret" \
  no_docker_call_holds "config credentials"
check "register-app.sh, the registration secret refused: before any docker call" no_docker_call

# registration-account.sh: the bootstrap administrator's password (a function's argument) refused,
# while the account doesn't log in: no other administrator is tried instead
cat > "$stack/.env" <<'EOF'
INFRA_ENV=dev
KC_REGISTRATION_CLIENT_ID=c4-registration
KC_REGISTRATION_CLIENT_SECRET=0123abcd
KC_BOOTSTRAP_ADMIN_USERNAME=admin
KC_BOOTSTRAP_ADMIN_PASSWORD=pa$word
EOF
FAKE_ACCOUNT_LOGIN=fails KC_SETUP_ADMIN_USERNAME=verif-setup KC_SETUP_ADMIN_PASSWORD=not-a-secret-0002 \
  stack_run registration-account.sh ensure
check "registration-account.sh, the bootstrap password refused: stops" refused
check "registration-account.sh, the bootstrap password refused: says so" \
  says "KC_BOOTSTRAP_ADMIN_PASSWORD of $stack/.env is refused"
check "registration-account.sh, the bootstrap password refused: no other administrator logs in" \
  no_docker_call_holds "--user verif-setup"
check "registration-account.sh, the bootstrap password refused: the account is left as it is" \
  no_docker_call_holds "create clients"
cat > "$stack/.env" <<'EOF'
INFRA_ENV=dev
KC_REGISTRATION_CLIENT_ID=c4-registration
KC_REGISTRATION_CLIENT_SECRET=ab$cd
EOF
stack_run registration-account.sh ensure
check "registration-account.sh, the registration secret refused: stops" refused
check "registration-account.sh, the registration secret refused: says so" \
  says "KC_REGISTRATION_CLIENT_SECRET of $stack/.env is refused"
check "registration-account.sh, the registration secret refused: no login with an empty secret" \
  no_docker_call_holds "config credentials"
finish
