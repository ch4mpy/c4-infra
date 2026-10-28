#!/usr/bin/env bash
# 0017: new-realm-ids.sh gives a realm export ids of its own (RQ-04: every script has a test), on a
# copy of tests/fixtures/0017/two-users-realm.json, a realm in Keycloak's export layout with two users:
# every UUID replaced by a random one, the same everywhere in the file, so that its references
# (containerId, parentId) still hold; the users' new ids printed; a file without ids reported.
#
#   bash tests/0017-new-realm-ids.sh
#
# covers: new-realm-ids.sh tests/fixtures/0017/two-users-realm.json
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

FIXTURE=tests/fixtures/0017/two-users-realm.json
UUID='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
V4='^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

realm=$work/realm.json
cp "$FIXTURE" "$realm"
bash new-realm-ids.sh "$realm" > "$work/out" 2>&1
status=$?

no_old_id() {
  local id
  for id in $(grep -oE "$UUID" "$FIXTURE" | sort -u); do
    ! grep -qF "$id" "$realm" || { echo "still there: $id"; return 1; }
  done
}

all_v4() {
  local id
  for id in $(grep -oE "$UUID" "$realm" | sort -u); do
    grep -qE "$V4" <<< "$id" || { echo "not a version 4 UUID: $id"; return 1; }
  done
}

user_printed() { # <username>: its old and new ids, as the file now holds the new one
  local old new
  old=$(jq -r --arg u "$1" '.users[] | select(.username == $u) | .id' "$FIXTURE")
  new=$(jq -r --arg u "$1" '.users[] | select(.username == $u) | .id' "$realm")
  grep -qxF "  user $1: $old -> $new" "$work/out" || { echo "output:"; cat "$work/out"; return 1; }
}

check "new-realm-ids.sh exits 0" test "$status" -eq 0
check "it says how many ids it replaced" grep -qxF "$realm: 5 ids replaced" "$work/out"
check "the file is still JSON" jq -e .realm "$realm"
check "no id of the fixture is left" no_old_id
check "every id is a random (version 4) UUID" all_v4
check "the five ids are still five different ones" test "$(grep -oE "$UUID" "$realm" | sort -u | wc -l)" -eq 5
check "the realm role's containerId is still the realm's id" jq -e '.roles.realm[0].containerId == .id' "$realm"
check "the component's parentId is still the realm's id" \
  jq -e '.components["org.keycloak.userprofile.UserProfileProvider"][0].parentId == .id' "$realm"
check "alice's old and new ids are printed" user_printed alice
check "bob's too" user_printed bob

echo '{ "realm" : "verif-no-id" }' > "$work/no-id.json"
cp "$work/no-id.json" "$work/no-id.before"
bash new-realm-ids.sh "$work/no-id.json" > "$work/out" 2>&1
check "a file without ids: exits 0" test $? -eq 0
check "a file without ids: reported" grep -qxF "$work/no-id.json: no id" "$work/out"
check "a file without ids: left as it was" cmp -s "$work/no-id.json" "$work/no-id.before"
finish
