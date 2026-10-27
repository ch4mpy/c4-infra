#!/usr/bin/env bash
# 0013: Keycloak's upgrade on a stand-in demo host (AC-01, AC-02, AC-07, RQ-03, RQ-04):
#
#   - the stack deployed as it was before 0013 ($BEFORE's files, its Keycloak 26.7 built from its
#     keycloak/ as c4-infra/keycloak:before); a realm, its user and a session (a refresh token) made
#     there;
#   - then this branch deployed (Keycloak 26.8.1, c4-infra/keycloak): deploy.sh says the image
#     changes, dumps Keycloak's database out of the nightly rotation, and stops Keycloak before the
#     new version's import runs; the realm, the user and the session are kept (the refresh token
#     refreshes), and the master realm's settings (0009, 0010); Keycloak's log names 26.8.1 and its
#     features;
#   - a second deployment, the same image: no dump, no stop.
#
#   bash tests/0013-upgrade.stand-in.sh      (bash tests/run.sh --all runs it)
#
# As the other stand-in tests: the images are this machine's, loaded into the stand-in; Let's Encrypt
# is kept out; passwords travel in files and on stdin.
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/stand-in-host.sh

# The stack before 0013: 0012's head (Keycloak 26.7, the master realm's one-shot import)
BEFORE=e493826
DIR=/root/c4-infra
REALM=verif-upgrade
CLIENT=verif-public

umask 077
work=$(mktemp -d)
trap 'stand_in_down; rm -rf "$work"' EXIT

# <log> <command…>: in the stack's directory on the stand-in, stdin closed, the output into
# $work/<log>, the exit status into $status
in_stack() {
  local log=$1
  shift
  MSYS_NO_PATHCONV=1 docker exec "$STAND_IN_NAME" bash -c 'cd "$1" && shift && "$@" < /dev/null' sh "$DIR" "$@" \
    > "$work/$log" 2>&1
  status=$?
}
exited() { # <expected status> <log>
  [ "$status" -eq "$1" ] || { echo "exit $status:"; tail -n 60 "$work/$2"; return 1; }
}
says() { # <log> <text>
  grep -qF -- "$2" "$work/$1" || { echo "output:"; tail -n 25 "$work/$1"; return 1; }
}
never_says() { # <log> <text>
  ! grep -qF -- "$2" "$work/$1" || { echo "output:"; tail -n 25 "$work/$1"; return 1; }
}
before() { # <log> <first text> <second text>: the first's line comes before the second's
  local first second
  first=$(grep -nF -m1 -- "$2" "$work/$1" | cut -d: -f1)
  second=$(grep -nF -m1 -- "$3" "$work/$1" | cut -d: -f1)
  [ -n "$first" ] && [ -n "$second" ] && [ "$first" -lt "$second" ] \
    || { echo "'$2' at line ${first:-none}, '$3' at line ${second:-none}:"; cat "$work/$1"; return 1; }
}
set_image() { # <KC_IMAGE>: in the stand-in's .env, as the workflow writes it for that version
  stand_in_exec sed -i "s|^KC_IMAGE=.*|KC_IMAGE=$1|" "$DIR/.env"
}
# The admin CLI in the stand-in's Keycloak, as the administrator of its .env (as data); -i passes
# stdin, which the caller redirects
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
# The realm's token endpoint, from the stand-in (Keycloak's address on the shared services' network);
# the form on stdin
token() {
  stand_in_exec -i bash -c 'address=$(docker inspect -f "{{(index .NetworkSettings.Networks \"c4-infra\").IPAddress}}" c4-infra.keycloak)
    curl -s -d @- "http://$address:8080/auth/realms/$1/protocol/openid-connect/token"' sh "$REALM"
}
master_settings() { # what 0009 and 0010 set, without the SMTP password
  kc_admin get realms/master < /dev/null 2> /dev/null \
    | jq -cS '{smtpServer: (.smtpServer | del(.password)), verifyEmail, resetPasswordAllowed, bruteForceProtected, failureFactor}'
}
keycloak_image() {
  stand_in_exec docker inspect -f '{{.Config.Image}}' c4-infra.keycloak | tr -d '\r'
}
dumps() { # the pre-upgrade dumps on the host
  stand_in_exec sh -c 'ls /root/backups/c4-infra-keycloak-before-upgrade-*.dump 2> /dev/null' | tr -d '\r'
}

check "the stand-in host starts" stand_in_up
check "Keycloak 26.7 is built from $BEFORE's keycloak/ (c4-infra/keycloak:before)" \
  bash -c 'git archive "$1:keycloak" | docker build -q -t c4-infra/keycloak:before - > /dev/null' sh "$BEFORE"
check "the images are loaded into it (before, this branch's Keycloak and proxy)" \
  stand_in_load_image c4-infra/keycloak:before c4-infra/keycloak c4-infra/reverse-proxy
stand_in_exec rm -rf "$DIR" /root/backups

# The stack before 0013
send_before() {
  stand_in_exec mkdir -p "$DIR" || return 1
  git archive "$BEFORE" $(git show "$BEFORE:demo/deploy-files.txt" | tr -d '\r') | stand_in_exec -i tar -xf - --no-same-owner -C "$DIR"
}
env_before() {
  stand_in_env "$DIR" && set_image c4-infra/keycloak:before
}
check "$BEFORE's files are sent" send_before
check ".env is written (demo/write-env.sh), its KC_IMAGE c4-infra/keycloak:before" env_before
in_stack before.log bash ./demo/deploy.sh
check "$BEFORE's deploy.sh exits 0" exited 0 before.log
check "Keycloak runs c4-infra/keycloak:before" test "$(keycloak_image)" = c4-infra/keycloak:before

# A realm, its user and a session
password=$(openssl rand -hex 16)
jq -n --arg realm "$REALM" --arg client "$CLIENT" --arg password "$password" '{
  realm: $realm, enabled: true,
  clients: [ { clientId: $client, publicClient: true, directAccessGrantsEnabled: true, standardFlowEnabled: false } ],
  users: [ { username: "verif.user", enabled: true, email: "verif.user@example.org", emailVerified: true, firstName: "Verif", lastName: "User",
             credentials: [ { type: "password", value: $password, temporary: false } ] } ]
}' > "$work/realm.json"
check "a realm with a user is created" kc_admin -i create realms -f - < "$work/realm.json"
printf 'grant_type=password&client_id=%s&username=verif.user&password=%s&scope=openid' "$CLIENT" "$password" | token > "$work/login.json"
refresh_token=$(jq -r '.refresh_token // empty' "$work/login.json" | tr -d '\r')
check "the user logs in: a session, its refresh token" test -n "$refresh_token"
master_before=$(master_settings)
check "the master realm's settings are read" test -n "$master_before"

# This branch
check "this branch's files are sent" stand_in_send "$DIR"
check ".env's KC_IMAGE is c4-infra/keycloak" set_image c4-infra/keycloak
in_stack upgrade.log bash ./demo/deploy.sh
[ "$status" -eq 0 ] || stand_in_exec docker logs --tail 40 c4-infra.keycloak-import >> "$work/upgrade.log" 2>&1
check "AC-07: deploy.sh exits 0" exited 0 upgrade.log
check "AC-07: it says Keycloak's image changes" says upgrade.log "Keycloak's image changes (c4-infra/keycloak:before → c4-infra/keycloak)"
check "AC-07: one pre-upgrade dump, out of the nightly rotation" test "$(dumps | wc -l)" -eq 1
check "AC-07: a PostgreSQL dump (custom format)" \
  stand_in_exec sh -c 'head -c 5 /root/backups/c4-infra-keycloak-before-upgrade-*.dump | grep -qx PGDMP'
check "AC-07: dumped before Keycloak stops" before upgrade.log "written to /root/backups/c4-infra-keycloak-before-upgrade-" "c4-infra.keycloak  Stopped"
check "RQ-03: Keycloak stopped before the new import starts" before upgrade.log "c4-infra.keycloak  Stopped" "c4-infra.keycloak-import  Started"
check "Keycloak runs c4-infra/keycloak" test "$(keycloak_image)" = c4-infra/keycloak
log=$(stand_in_exec docker logs c4-infra.keycloak 2>&1 | tr -d '\r')
check "AC-01: Keycloak 26.8.1" grep -qF "Keycloak 26.8.1 on JVM" <<< "$log"
check "AC-01: its preview features" grep -qF "Preview features enabled: parameterized-scopes:v1, token-exchange-delegation:v1" <<< "$log"
check "AC-01: its experimental feature" grep -qF "Experimental features enabled: cimd:v1" <<< "$log"
user_kept() {
  kc_admin get users -r "$REALM" -q username=verif.user -q exact=true < /dev/null 2> /dev/null | jq -e 'length == 1' > /dev/null
}
check "AC-02: the user is kept" user_kept
printf 'grant_type=refresh_token&client_id=%s&refresh_token=%s' "$CLIENT" "$refresh_token" | token > "$work/refresh.json"
check "AC-02: the session is kept: its refresh token refreshes ($(jq -c '.error // "ok"' "$work/refresh.json"))" \
  test -n "$(jq -r '.access_token // empty' "$work/refresh.json" | tr -d '\r')"
check "AC-02: the master realm's settings are kept" test "$(master_settings)" = "$master_before"

# The same image again
in_stack again.log bash ./demo/deploy.sh
check "a second deployment exits 0" exited 0 again.log
check "it doesn't say the image changes" never_says again.log "Keycloak's image changes"
check "it dumps nothing" test "$(dumps | wc -l)" -eq 1
check "it doesn't stop Keycloak" never_says again.log "c4-infra.keycloak  Stopped"
finish
