#!/usr/bin/env bash
# 0017: export-realm.sh exports a realm of the running dev stack (RQ-04: every script has a test):
# 0010's fixture realm, verif-lockout, registered with register-app.sh, then exported to a temporary
# directory: <realm>-realm.json holds its user and none of its keys, and Keycloak kept running.
#
#   bash tests/0017-export-realm.sh
#
# Needs the dev stack running and jq. The fixture realm and its network are removed whatever happens.
# covers: export-realm.sh up.sh env.sh compose.yml compose.dev.yml keycloak/ register-app.sh
# covers: registry.sh networks.sh registration-account.sh routes.sh tests/fixtures/0010/
# covers: registry.txt tlds-alpha-by-domain.txt caddy/ keycloak-import/ reverse-proxy/ certs/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/keycloak.sh

FIXTURE=tests/fixtures/0010
REALM=verif-lockout
export MSYS_NO_PATHCONV=1

work=$(mktemp -d)
remove_fixture() {
  kc_registration delete "realms/$REALM" > /dev/null 2>&1
  bash networks.sh remove "$REALM" > /dev/null
}
trap 'remove_fixture; rm -rf "$work"' EXIT
remove_fixture

logged() { # <log> <command…>: runs it, its output in $work/<log>, shown when it fails
  local log=$1
  shift
  "$@" > "$work/$log" 2>&1 || { echo "exit $?"; tail -n 15 "$work/$log"; return 1; }
}

no_key() {
  ! grep -n '"privateKey"\|"certificate"' "$exported"
}

keycloak_started() {
  docker inspect -f '{{.State.StartedAt}}' c4-infra.keycloak
}

check "$REALM registers" logged register.log env REGISTRY_FILE="$PWD/$FIXTURE/registry.txt" \
  bash register-app.sh --app "$REALM" --realm "$FIXTURE/$REALM-realm.json"
started=$(keycloak_started)

exported=$work/export/$REALM-realm.json
check "export-realm.sh exits 0" logged export.log bash export-realm.sh "$REALM" "$work/export"
check "it writes $REALM-realm.json" test -s "$exported"
check "the export is the realm's" jq -e --arg r "$REALM" '.realm == $r' "$exported"
check "with its user" jq -e '[.users[].username] == ["visitor"]' "$exported"
check "without its keys: no key provider" jq -e '.components["org.keycloak.keys.KeyProvider"] == []' "$exported"
check "without its keys: no private key nor certificate anywhere" no_key
check "Keycloak kept running (the same start)" test "$(keycloak_started)" = "$started"
check "and is healthy" test "$(docker inspect -f '{{.State.Health.Status}}' c4-infra.keycloak)" = healthy
finish
