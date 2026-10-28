#!/usr/bin/env bash
# 0016: the demo host's deployment brings the simulated providers' realms to a stack that runs
# without them (AC-01, AC-02), on a stand-in demo host:
#
#   - the stack of f4c3620 (main before 0016: no simulated realm, its Keycloak image built here from
#     that commit's keycloak/) deployed, a realm with a user created on it, the master realm's
#     settings read;
#   - this branch deployed (its files, its Keycloak image: the stack themes): it exits 0, the three
#     simulated realms exist, each one's discovery names its issuer
#     https://infra.c4-soft.com/auth/realms/<name>, the realm and its user are kept, the master
#     realm's settings too;
#   - deployed again: it exits 0, keycloak-import skips the three realms, which are as they were.
#
#   bash tests/0016-simulated.stand-in.sh
#
# covers: keycloak-import/ keycloak/ demo/ compose.yml compose.demo.yml tests/stand-in-host/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/stand-in-host.sh

# The stack before 0016: main's head before it
BEFORE=f4c3620
DIR=/root/c4-infra
HOST=infra.c4-soft.com
REALM=verif-simulated
SIMULATED=(simulated-google simulated-facebook simulated-apple)

umask 077
work=$(mktemp -d)
trap 'stand_in_down; rm -rf "$work"' EXIT

in_stack() { # <log> <command…>: in the stack's directory on the stand-in, its output in $work/<log>, $status
  local log=$1
  shift
  MSYS_NO_PATHCONV=1 docker exec "$STAND_IN_NAME" bash -c 'cd "$1" && shift && "$@" < /dev/null' sh "$DIR" "$@" \
    > "$work/$log" 2>&1
  status=$?
}
exited_0() { # <log>
  [ "$status" -eq 0 ] || { echo "exit $status:"; tail -n 40 "$work/$1"; return 1; }
}
set_image() { # <KC_IMAGE>
  stand_in_exec sed -i "s|^KC_IMAGE=.*|KC_IMAGE=$1|" "$DIR/.env"
}
# The admin CLI in the stand-in's Keycloak, as the administrator of its .env (read as data)
kc_admin() { # [-i] <kcadm args…>
  local io=""
  if [ "${1:-}" = -i ]; then
    io=-i
    shift
  fi
  MSYS_NO_PATHCONV=1 docker exec $io "$STAND_IN_NAME" bash -c '
    cd "$1"; io=$2; shift 2
    value() { grep -m1 "^$1=" .env | cut -d= -f2-; }
    KC_CLI_PASSWORD=$(value KC_BOOTSTRAP_ADMIN_PASSWORD)
    export KC_CLI_PASSWORD
    docker exec $io -e KC_CLI_PASSWORD c4-infra.keycloak /opt/keycloak/bin/kcadm.sh "$@" \
      --no-config --server http://localhost:8080/auth --realm master --user "$(value KC_BOOTSTRAP_ADMIN_USERNAME)"' \
    sh "$DIR" "$io" "$@"
}
realms() { kc_admin get realms --fields realm < /dev/null 2> /dev/null | jq -r '.[].realm' | sort | paste -sd' ' -; }
master_settings() {
  kc_admin get realms/master < /dev/null 2> /dev/null \
    | jq -cS '{smtpServer: (.smtpServer | del(.password)), verifyEmail, resetPasswordAllowed, bruteForceProtected, failureFactor}'
}
users_of() { # <realm>
  kc_admin get users -r "$1" < /dev/null 2> /dev/null | jq -cS 'map({username, email, createdTimestamp}) | sort_by(.username)'
}
issuer() { # <realm>: from the proxy's container, on the stack's network
  stand_in_exec docker exec c4-infra.reverse-proxy wget -qO- "http://keycloak:8080/auth/realms/$1/.well-known/openid-configuration" \
    | jq -r .issuer
}
simulated_state() {
  local realm
  for realm in "${SIMULATED[@]}"; do
    kc_admin get "realms/$realm" --fields id,realm,loginTheme,registrationAllowed < /dev/null 2> /dev/null | jq -cS .
    users_of "$realm"
  done
}

check "the stand-in host starts" stand_in_up
check "the Keycloak image of $BEFORE is built here (c4-infra/keycloak:before-0016)" \
  bash -c 'git archive "$1:keycloak" | docker build -q -t c4-infra/keycloak:before-0016 - > /dev/null' sh "$BEFORE"
check "the images are loaded into it (before, this branch's Keycloak and proxy)" \
  stand_in_load_image c4-infra/keycloak:before-0016 c4-infra/keycloak c4-infra/reverse-proxy
stand_in_exec rm -rf "$DIR" /root/backups

send_before() {
  stand_in_exec mkdir -p "$DIR" || return 1
  git archive "$BEFORE" $(git show "$BEFORE:demo/deploy-files.txt" | tr -d '\r') | stand_in_exec -i tar -xf - --no-same-owner -C "$DIR"
}
check "$BEFORE's files are sent" send_before
env_before() {
  stand_in_env "$DIR" && set_image c4-infra/keycloak:before-0016
}
check ".env is written (demo/write-env.sh), its KC_IMAGE c4-infra/keycloak:before-0016" env_before
in_stack before.log bash ./demo/deploy.sh
check "$BEFORE's deploy.sh exits 0" exited_0 before.log
check "no simulated realm before 0016 ($(realms))" eval '[[ " $(realms) " != *" simulated-"* ]]'

jq -n --arg realm "$REALM" '{ realm: $realm, enabled: true,
  users: [ { username: "verif.user", enabled: true, email: "verif.user@example.org", emailVerified: true,
             firstName: "Verif", lastName: "User" } ] }' > "$work/realm.json"
check "a realm with a user is created" kc_admin -i create realms -f - < "$work/realm.json"
users_before=$(users_of "$REALM")
master_before=$(master_settings)
check "its user and the master realm's settings are read" test -n "$users_before" -a -n "$master_before"

check "this branch's files are sent" stand_in_send "$DIR"
check ".env's KC_IMAGE is this branch's c4-infra/keycloak" set_image c4-infra/keycloak
in_stack deploy.log bash ./demo/deploy.sh
[ "$status" -eq 0 ] || stand_in_exec docker logs --tail 40 c4-infra.keycloak-import >> "$work/deploy.log" 2>&1
check "AC-01: this branch's deploy.sh exits 0" exited_0 deploy.log
for realm in "${SIMULATED[@]}"; do
  check "AC-01: realm $realm exists" eval '[[ " $(realms) " == *" $realm "* ]]'
  check "AC-02: its issuer is https://$HOST/auth/realms/$realm" test "$(issuer "$realm")" = "https://$HOST/auth/realms/$realm"
done
check "AC-01: realm $REALM and its user are kept" test "$(users_of "$REALM")" = "$users_before"
check "AC-01: the master realm's settings are kept" test "$(master_settings)" = "$master_before"

state=$(simulated_state)
in_stack again.log bash ./demo/deploy.sh
check "AC-01: deployed again: exits 0" exited_0 again.log
import_log=$(stand_in_exec docker logs c4-infra.keycloak-import 2>&1 | tr -d '\r')
for realm in "${SIMULATED[@]}"; do
  check "AC-01: keycloak-import skips $realm" grep -qF "Realm '$realm' already exists. Import skipped" <<< "$import_log"
done
check "AC-01: the simulated realms are as they were" test "$(simulated_state)" = "$state"
check "AC-01: realm $REALM's user is still kept" test "$(users_of "$REALM")" = "$users_before"
finish
