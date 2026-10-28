#!/usr/bin/env bash
# 0030: new-realm-ids.sh renews every id an import needs unique, a user federation's short id and its
# users' links included, on copies of tests/fixtures/0030/verif-ldap-realm.json (an LDAP component
# with a short id, two mappers, two users linked to it, a local one):
#
#   - the files: two copies a and b, each through the script: no id of the fixture left, the
#     component's id in Keycloak's short form and not the same in a and b, each linked user's
#     federationLink and origin its own copy's component, the layout kept; c, a copy of a run again,
#     renewed again; a readable id refused, its file left as it was; a storage id f:<component>:<…>,
#     in jq's layout, following its component;
#   - Keycloak: a, b and c imported into a throwaway of the stack's image as register-app.sh imports
#     a realm: each imported, each holding its own component, its users linked to it.
#
#   bash tests/0030-federation-ids.sh
#
# Needs the image c4-infra/keycloak (up.sh builds it). The throwaway is removed whatever happens.
#
# covers: new-realm-ids.sh tests/fixtures/0030/ keycloak/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/keycloak.sh

FIXTURE=tests/fixtures/0030/verif-ldap-realm.json
IMAGE=c4-infra/keycloak
NAME=c4-infra.0030-test
NETWORK=c4-infra-0030-test
SERVER=http://localhost:8080/auth
UUID='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
SHORT='^[A-Za-z0-9_-]{22}$'
LDAP=org.keycloak.storage.UserStorageProvider
MAPPERS=org.keycloak.storage.ldap.mappers.LDAPStorageMapper
export MSYS_NO_PATHCONV=1

host_path() { if command -v cygpath > /dev/null; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

umask 022
work=$(mktemp -d)
cleanup() {
  docker rm -f "$NAME" > /dev/null 2>&1
  docker network rm "$NETWORK" > /dev/null 2>&1
  rm -rf "$work"
}
trap cleanup EXIT

component() { jq -r --arg t "$LDAP" '.components[$t][0].id' "$1"; }
mappers() { jq -r --arg t "$LDAP" --arg m "$MAPPERS" '.components[$t][0].subComponents[$m][].id' "$1"; }
renew() { # <copy>: the script on $work/<copy>.json; its output in <copy>.out, its exit status in <copy>.status
  bash new-realm-ids.sh "$work/$1.json" > "$work/$1.out" 2>&1
  echo $? > "$work/$1.status"
}
exited() { # <copy> <status>
  [ "$(cat "$work/$1.status")" = "$2" ] || { echo "exit $(cat "$work/$1.status"); output:"; cat "$work/$1.out"; return 1; }
}
no_fixture_id() { # <copy>
  local id
  for id in $(grep -oE "$UUID" "$FIXTURE" | LC_ALL=C sort -u) "$(component "$FIXTURE")"; do
    ! grep -qF "$id" "$work/$1.json" || { echo "still there: $id"; return 1; }
  done
}
short_renewed() { # <copy>: its component's id has Keycloak's short form, and isn't the fixture's
  local id
  id=$(component "$work/$1.json")
  grep -qE "$SHORT" <<< "$id" && [ "$id" != "$(component "$FIXTURE")" ] || { echo "component: $id"; return 1; }
}
linked() { # <copy>: each linked user's federationLink and origin are its own component; the local user has none
  jq -e --arg t "$LDAP" '.components[$t][0].id as $c
    | ([.users[] | select(.username != "verif-local") | .federationLink, .origin] | length == 4 and all(. == $c))
      and ([.users[] | select(.username == "verif-local") | .federationLink, .origin] | all(. == null))' "$work/$1.json"
}
masked() { sed -E "s/$UUID/<uuid>/g; s/\"[A-Za-z0-9_-]{22}\"/\"<short>\"/g" "$1"; }
same_layout() { # <copy>: the fixture once every id is masked
  diff <(masked "$FIXTURE") <(masked "$work/$1.json")
}
differ() { # <a> <b>
  [ "$1" != "$2" ] || { echo "both: $1"; return 1; }
}

# The files
ids=$(($(grep -oE "$UUID" "$FIXTURE" | LC_ALL=C sort -u | wc -l) + 1))
cp "$FIXTURE" "$work/a.json"
cp "$FIXTURE" "$work/b.json"
for copy in a b; do
  renew "$copy"
  check "$copy: new-realm-ids.sh exits 0" exited "$copy" 0
  check "$copy: it counts the component's id among the $ids it replaced" grep -qxF "$work/$copy.json: $ids ids replaced" "$work/$copy.out"
  check "$copy: no id of the fixture is left, the component's included" no_fixture_id "$copy"
  check "$copy: the component's new id has Keycloak's short form" short_renewed "$copy"
  check "$copy: each linked user's federationLink and origin follow it; the local user has none" linked "$copy"
  check "$copy: the layout is kept" same_layout "$copy"
done
check "a and b: their components' ids differ" differ "$(component "$work/a.json")" "$(component "$work/b.json")"
check "a and b: their mappers' ids differ" differ "$(mappers "$work/a.json")" "$(mappers "$work/b.json")"

cp "$work/a.json" "$work/c.json"
renew c
check "c, a run again: exits 0" exited c 0
check "c: its component's id renewed again" differ "$(component "$work/a.json")" "$(component "$work/c.json")"
check "c: its users still linked to it" linked c

sed 's/"id" : "0a30c7d1-5e2b-4f6a-9c3e-7b8d9e0f1a2b"/"id" : "verif-readable"/' "$FIXTURE" > "$work/readable.json"
cp "$work/readable.json" "$work/readable.before"
renew readable
check "a readable id: refused, exit 1" exited readable 1
check "a readable id: named" grep -qF verif-readable "$work/readable.out"
check "a readable id: the file left as it was" cmp -s "$work/readable.json" "$work/readable.before"

jq --arg c "$(component "$FIXTURE")" '. + {federatedUsers: [{id: ("f:" + $c + ":verif-external")}]}' "$FIXTURE" > "$work/storage.json"
renew storage
check "a storage id, in jq's layout: exits 0" exited storage 0
check "a storage id: its component part follows the component" \
  jq -e --arg t "$LDAP" '.federatedUsers[0].id == "f:" + .components[$t][0].id + ":verif-external"' "$work/storage.json"
check "a storage id: the component renewed" short_renewed storage

# Keycloak: a, b and c imported as register-app.sh imports a realm (kcadm, the file on stdin)
KC_CLI_PASSWORD=$(openssl rand -hex 16)
export KC_CLI_PASSWORD
printf '%s\n' KC_BOOTSTRAP_ADMIN_USERNAME=admin "KC_BOOTSTRAP_ADMIN_PASSWORD=$KC_CLI_PASSWORD" > "$work/admin.env"
chmod 600 "$work/admin.env"
admin() { # <kcadm args…>: as the throwaway's administrator, the request's JSON on stdin
  docker exec -i -e KC_CLI_PASSWORD "$NAME" /opt/keycloak/bin/kcadm.sh "$@" \
    --no-config --server "$SERVER" --realm master --user admin 2> "$work/admin.err"
}
said() { echo "kcadm:"; cat "$work/admin.err"; return 1; }
docker rm -f "$NAME" > /dev/null 2>&1
docker network rm "$NETWORK" > /dev/null 2>&1
docker network create "$NETWORK" > /dev/null
docker run -d --name "$NAME" --network "$NETWORK" --env-file "$(host_path "$work/admin.env")" \
  "$IMAGE" start-dev --db=dev-file > /dev/null
check "the throwaway Keycloak answers its readiness probe" kc_throwaway_ready "$NAME"

for copy in a b c; do
  realm=verif-0030-$copy
  check "$copy: imported as $realm" eval 'admin create realms -f - -s "realm=$realm" < "$work/$copy.json" > /dev/null || said'
  check "$copy: $realm holds its own component" \
    eval '[ "$(admin get components -r "$realm" -q "type=$LDAP" --fields id | jq -r ".[].id")" = "$(component "$work/$copy.json")" ] || said'
  check "$copy: its verif-linked-1 is linked to it" \
    eval '[ "$(admin get users -r "$realm" -q username=verif-linked-1 -q exact=true --fields federationLink | jq -r ".[0].federationLink")" = "$(component "$work/$copy.json")" ] || said'
done
finish
