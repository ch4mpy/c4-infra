#!/usr/bin/env bash
# 0010: c4-infra's brute-force protection (RQ-01): a temporary lockout after 10 failures, 1 more
# minute per further failure, at most 15 minutes, never for good; on the applications' realms only,
# for the settings their exports don't hold (0041: each one an export holds is kept).
#
#   - the dev stack's master realm has no detection (AC-01), and the registration account may not
#     change its settings (AC-08);
#   - register-app.sh imports the fixture realm verif-lockout (its export holds three settings: the
#     detection off, 30 failures, MULTIPLE) with those three and RQ-01's seven others, naming the
#     seven, and says it has no detection (0041 AC-01); a realm already in Keycloak keeps its own
#     until --reset-realms imports it again (AC-05, 0041 AC-03); a copy holding none of the ten,
#     imported again, gets RQ-01's ten, all named (0041 AC-02);
#   - that realm's user locks after its 10th failure, not its 9th, and logs in again a minute later
#     (AC-03).
#
#   bash tests/0010-brute-force.sh
#
# Needs the dev stack running and jq. The fixture realm and its network are removed whatever happens.
#
# covers: up.sh env.sh compose.yml compose.dev.yml caddy/ keycloak/ keycloak-import/ reverse-proxy/
# covers: certs/ register-app.sh registry.sh registry.txt routes.sh networks.sh
# covers: registration-account.sh tlds-alpha-by-domain.txt tests/fixtures/0010/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/keycloak.sh

FIXTURE=tests/fixtures/0010
REALM=verif-lockout
VISITOR_PASSWORD=visitor-password
# RQ-01, as Keycloak answers them; SETTINGS picks the same keys from a realm
EXPECTED='{"bruteForceProtected":true,"bruteForceStrategy":"LINEAR","failureFactor":10,"maxDeltaTimeSeconds":43200,"maxFailureWaitSeconds":900,"maxTemporaryLockouts":0,"minimumQuickLoginWaitSeconds":60,"permanentLockout":false,"quickLoginCheckMilliSeconds":1000,"waitIncrementSeconds":60}'
SETTINGS="{$(jq -r 'keys | join(", ")' <<< "$EXPECTED")}"
# the fixture's export: its three settings, RQ-01's seven others
FROM_EXPORT='{"bruteForceProtected":false,"bruteForceStrategy":"MULTIPLE","failureFactor":30,"maxDeltaTimeSeconds":43200,"maxFailureWaitSeconds":900,"maxTemporaryLockouts":0,"minimumQuickLoginWaitSeconds":60,"permanentLockout":false,"quickLoginCheckMilliSeconds":1000,"waitIncrementSeconds":60}'
export MSYS_NO_PATHCONV=1

umask 077
work=$(mktemp -d)
# the fixture's realm and network (its own: an earlier run's too), and its compose.apps.yml entry;
# the registration account, which created the realm, deletes it: no administrator needed
remove_fixture() {
  kc_registration delete "realms/$REALM" > /dev/null 2>&1
  bash networks.sh remove "$REALM" > /dev/null
}
trap 'remove_fixture; rm -rf "$work"' EXIT
remove_fixture

# AC-01, AC-08: the master realm (bruteForceProtected is in the registration account's reduced view)
check "AC-01: the master realm's import sets no brute-force detection (Keycloak's default: off)" \
  jq -e 'has("bruteForceProtected") | not' keycloak-import/master-realm.json
check "AC-01: the dev stack's master realm has none" \
  test "$(kc_registration get realms/master 2> /dev/null | jq -c .bruteForceProtected)" = false
# the probe changes nothing even if Keycloak accepted it
refused_403() {
  local output
  if output=$(kc_registration update realms/master -s bruteForceProtected=false 2>&1); then
    echo "succeeded"
    return 1
  fi
  grep -qF 403 <<< "$output" || { printf '%s\n' "$output" | tail -n 3; return 1; }
}
check "AC-08: the registration account may not change the master realm's settings (403)" refused_403

# The fixture realm, through register-app.sh, as an application registers it
register() { # <log> <realm file> [option…]
  local log=$1 file=$2
  shift 2
  REGISTRY_FILE=$PWD/$FIXTURE/registry.txt bash register-app.sh --app "$REALM" --realm "$file" "$@" \
    > "$work/$log" 2>&1
  status=$?
}
says() { # <log> <text>
  [ "$status" -eq 0 ] || { echo "exit $status"; tail -n 15 "$work/$1"; return 1; }
  grep -qxF -- "$2" "$work/$1" || { tail -n 15 "$work/$1"; return 1; }
}
has_settings() { # <expected>
  local actual
  actual=$(kc_registration get "realms/$REALM" 2> /dev/null | jq -cS "$SETTINGS")
  [ "$actual" = "$1" ] || { echo "settings: $actual"; echo "expected: $1"; return 1; }
}

register import.log "$FIXTURE/$REALM-realm.json"
check "AC-02: register-app.sh imports $REALM" says import.log "Importing realm $REALM"
check "0041 AC-01: it names the seven settings the stack filled" says import.log \
  "Realm $REALM: brute-force settings from its export, the stack's for permanentLockout, maxTemporaryLockouts, waitIncrementSeconds, maxFailureWaitSeconds, maxDeltaTimeSeconds, quickLoginCheckMilliSeconds, minimumQuickLoginWaitSeconds"
check "0041 AC-01: and says the realm has no detection" says import.log \
  "Realm $REALM: no brute-force detection, as its export says (README.md, \"Brute-force protection\")"
check "0041 AC-01: $REALM has its export's three settings and RQ-01's seven others" has_settings "$FROM_EXPORT"

# AC-05, 0041 AC-03: a realm already there keeps its own
check "AC-05: the registration account turns $REALM's detection on" \
  kc_registration update "realms/$REALM" -s bruteForceProtected=true
register again.log "$FIXTURE/$REALM-realm.json"
check "AC-05: registered again, $REALM is left as it is" says again.log "Realm $REALM: already in Keycloak, left as it is"
check "AC-05: its detection stays on" \
  test "$(kc_registration get "realms/$REALM" --fields bruteForceProtected 2> /dev/null | jq -c .bruteForceProtected)" = true

# 0041 AC-02: an export without any of the ten settings gets RQ-01's ten
mkdir "$work/none"
jq --argjson e "$EXPECTED" 'delpaths($e | keys | map([.]))' < "$FIXTURE/$REALM-realm.json" > "$work/none/$REALM-realm.json"
register reset.log "$work/none/$REALM-realm.json" --reset-realms
check "AC-05: with --reset-realms, it is imported again" says reset.log "Importing realm $REALM"
check "0041 AC-02: a copy holding none of the ten: all named as the stack's" says reset.log \
  "Realm $REALM: brute-force settings from its export, the stack's for bruteForceProtected, permanentLockout, maxTemporaryLockouts, failureFactor, bruteForceStrategy, waitIncrementSeconds, maxFailureWaitSeconds, maxDeltaTimeSeconds, quickLoginCheckMilliSeconds, minimumQuickLoginWaitSeconds"
check "0041 AC-02: no line saying it has no detection" eval '! grep -qF "no brute-force detection" "$work/reset.log"'
check "0041 AC-02: $REALM has RQ-01's ten settings (no permanent lockout, 15 minutes at most)" has_settings "$EXPECTED"

# AC-03: the first lockout. The visitor's password grant through the fixture's public client, its
# password (a fixture's, no secret) in the CLI's environment; failures more than a second apart, or
# Keycloak's quick-login rule would lock it at once
visitor_login() { # <password>
  KC_CLI_PASSWORD=$1 docker exec -e KC_CLI_PASSWORD c4-infra.keycloak sh -c '
    session=/dev/shm/c4-0010-visitor-$$.kcadm
    trap "rm -f $session" EXIT
    /opt/keycloak/bin/kcadm.sh config credentials --config "$session" --server http://localhost:8080/auth \
      --realm "$1" --user visitor --client verif-cli' sh "$REALM" < /dev/null
}
refused_login() { ! visitor_login "$1" > /dev/null 2>&1; }
visitor_id=$(kc_registration get users -r "$REALM" -q username=visitor --fields id 2> /dev/null | jq -r '.[0].id')
disabled() { kc_registration get "attack-detection/brute-force/users/$visitor_id" -r "$REALM" 2> /dev/null | jq -r .disabled; }
check "AC-03: the visitor logs in with its password" visitor_login "$VISITOR_PASSWORD"
for i in 1 2 3 4 5 6 7 8 9; do
  visitor_login wrong-password > /dev/null 2>&1
  sleep 1.2
done
check "AC-03: after 9 failures, the visitor isn't locked" test "$(disabled)" = false
visitor_login wrong-password > /dev/null 2>&1
check "AC-03: after the 10th, it is locked" test "$(disabled)" = true
check "AC-03: its right password is refused meanwhile" refused_login "$VISITOR_PASSWORD"
sleep 61
check "AC-03: a minute later, its right password logs in" visitor_login "$VISITOR_PASSWORD"
finish
