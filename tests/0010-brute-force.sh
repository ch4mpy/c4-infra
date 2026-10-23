#!/usr/bin/env bash
# 0010: c4-infra's brute-force protection (REQ-1): a temporary lockout after 10 failures, 1 more
# minute per further failure, at most 15 minutes, never for good; on the applications' realms only.
#
#   - the dev stack's master realm has no detection (AC-1), and the registration account may not
#     change its settings (AC-8);
#   - register-app.sh imports the fixture realm verif-lockout (its export: the detection off, 30
#     failures) with REQ-1's settings (AC-2, AC-7); a realm already in Keycloak keeps its own until
#     --reset-realms imports it again (AC-5);
#   - verif-lockout's user locks after its 10th failure, not its 9th, and logs in again a minute
#     later (AC-3).
#
#   bash tests/0010-brute-force.sh
#
# Needs the dev stack running and jq. The fixture realm and its network are removed whatever happens.
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/keycloak.sh

FIXTURE=tests/fixtures/0010
REALM=verif-lockout
VISITOR_PASSWORD=visitor-password
# REQ-1, as Keycloak answers them; SETTINGS picks the same keys from a realm
EXPECTED='{"bruteForceProtected":true,"bruteForceStrategy":"LINEAR","failureFactor":10,"maxDeltaTimeSeconds":43200,"maxFailureWaitSeconds":900,"maxTemporaryLockouts":0,"minimumQuickLoginWaitSeconds":60,"permanentLockout":false,"quickLoginCheckMilliSeconds":1000,"waitIncrementSeconds":60}'
SETTINGS="{$(jq -r 'keys | join(", ")' <<< "$EXPECTED")}"
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

# AC-1, AC-8: the master realm (bruteForceProtected is in the registration account's reduced view)
check "AC-1: the master realm's import sets no brute-force detection (Keycloak's default: off)" \
  jq -e 'has("bruteForceProtected") | not' keycloak-import/master-realm.json
check "AC-1: the dev stack's master realm has none" \
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
check "AC-8: the registration account may not change the master realm's settings (403)" refused_403

# The fixture realm, through register-app.sh, as an application registers it
register() { # <log> [option…]
  local log=$1
  shift
  REGISTRY_FILE=$PWD/$FIXTURE/registry.txt bash register-app.sh --app "$REALM" --realm "$FIXTURE/$REALM-realm.json" "$@" \
    > "$work/$log" 2>&1
  status=$?
}
says() { # <log> <text>
  [ "$status" -eq 0 ] || { echo "exit $status"; tail -n 15 "$work/$1"; return 1; }
  grep -qF -- "$2" "$work/$1" || { tail -n 15 "$work/$1"; return 1; }
}
has_req_1() {
  local actual
  actual=$(kc_registration get "realms/$REALM" 2> /dev/null | jq -cS "$SETTINGS")
  [ "$actual" = "$EXPECTED" ] || { echo "settings: $actual"; echo "expected: $EXPECTED"; return 1; }
}

register import.log
check "AC-2: register-app.sh imports $REALM" says import.log "Importing realm $REALM"
check "AC-2: and says it set the brute-force protection" says import.log "Realm $REALM: brute-force protection set"
check "AC-2, AC-7: $REALM has REQ-1's settings, whatever its export said (no permanent lockout, 15 minutes at most)" has_req_1

# AC-5: a realm already there keeps its own
check "AC-5: the registration account turns $REALM's detection off" \
  kc_registration update "realms/$REALM" -s bruteForceProtected=false
register again.log
check "AC-5: registered again, $REALM is left as it is" says again.log "Realm $REALM: already in Keycloak, left as it is"
check "AC-5: its detection stays off" \
  test "$(kc_registration get "realms/$REALM" --fields bruteForceProtected 2> /dev/null | jq -c .bruteForceProtected)" = false
register reset.log --reset-realms
check "AC-5: with --reset-realms, it is imported again" says reset.log "Importing realm $REALM"
check "AC-5: with REQ-1's settings" has_req_1

# AC-3: the first lockout. The visitor's password grant through the fixture's public client, its
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
check "AC-3: the visitor logs in with its password" visitor_login "$VISITOR_PASSWORD"
for i in 1 2 3 4 5 6 7 8 9; do
  visitor_login wrong-password > /dev/null 2>&1
  sleep 1.2
done
check "AC-3: after 9 failures, the visitor isn't locked" test "$(disabled)" = false
visitor_login wrong-password > /dev/null 2>&1
check "AC-3: after the 10th, it is locked" test "$(disabled)" = true
check "AC-3: its right password is refused meanwhile" refused_login "$VISITOR_PASSWORD"
sleep 61
check "AC-3: a minute later, its right password logs in" visitor_login "$VISITOR_PASSWORD"
finish
