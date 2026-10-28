#!/usr/bin/env bash
# 0009: the Keycloak behaviours the master realm's pre-configuration relies on (RQ-01 to RQ-04),
# checked in throwaway Keycloaks of the stack's image (start-dev on a file database, no published
# port, their values in --env-files of a temporary directory):
#
#   (a) an import file's ${VAR} takes the variable from Keycloak's environment; ${env.VAR} doesn't;
#   (b) with --import-realm, a master realm in the import directory is imported on an empty
#       database, its administrator (realm role admin, a verified address, a password from the
#       environment) logs in with the admin CLI while verifyEmail is on, given the user profile of a
#       master realm Keycloak creates itself; with the default user profile of an imported realm
#       (firstName and lastName required), Keycloak refuses that login ("Account is not fully set up");
#   (c) Keycloak aborts its start when KC_BOOTSTRAP_ADMIN_* name the user the import holds: the
#       container gets the administrator under other names;
#   (d) a quoted "true" becomes the boolean resetPasswordAllowed;
#   (e) on that imported realm, an administrator creates the registration account, which creates and
#       manages a realm;
#   (f) restarted with another import file, the master realm stays as it was ("Import skipped");
#   (g) with verifyEmail on, an administrator without an address still logs in with the admin CLI;
#       one with an address not verified is refused, and logs in once it is verified (26.8.1 stores no
#       required action on the refusal; 26.7 did, to remove by hand);
#   (h) a value holding a double quote breaks the import: Keycloak doesn't start;
#   (i) a master realm Keycloak creates has accessTokenLifespan 60, displayName Keycloak, and a user
#       profile where email, firstName and lastName aren't required.
#
#   bash tests/0009-master-import-facts.sh
#
# Needs the image c4-infra/keycloak (up.sh builds it). The throwaway containers are removed whatever
# happens.
#
# covers: keycloak/ keycloak-import/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

IMAGE=c4-infra/keycloak
PREFIX=c4-infra.0009-facts
SERVER=http://localhost:8080/auth
KCADM=/opt/keycloak/bin/kcadm.sh
export MSYS_NO_PATHCONV=1

host_path() {
  if command -v cygpath > /dev/null; then cygpath -w "$1"; else printf '%s' "$1"; fi
}

umask 077
work=$(mktemp -d)
trap 'docker rm -f $(docker ps -aq -f "name=^$PREFIX-") > /dev/null 2>&1; rm -rf "$work"' EXIT

KC_CLI_PASSWORD=$(openssl rand -hex 16)
export KC_CLI_PASSWORD

# <name> <env file> [<import dir>]: a throwaway Keycloak, started in the background
start() {
  local args=(-d --name "$PREFIX-$1" --env-file "$(host_path "$2")")
  [ -z "${3:-}" ] || args+=(-v "$(host_path "$3"):/opt/keycloak/data/import:ro")
  docker run "${args[@]}" "$IMAGE" start-dev --db=dev-file ${3:+--import-realm} > /dev/null
}
# <name>: ready within 240 s, or stopped (returns 1 either way when not ready)
ready() {
  local waited=0
  until docker exec "$PREFIX-$1" java -cp /opt/keycloak/healthcheck HealthCheck http://localhost:9000/auth/health/ready > /dev/null 2>&1; do
    if [ -z "$(docker ps -q -f "name=^$PREFIX-$1$")" ] || [ "$waited" -ge 240 ]; then
      echo "not ready ($waited s); its log:"
      docker logs --tail 5 "$PREFIX-$1" 2>&1
      return 1
    fi
    sleep 2
    waited=$((waited + 2))
  done
}
# <name> <user> <password> <kcadm args…>: the admin CLI as that user of the master realm
as() {
  local name=$1 user=$2
  KC_CLI_PASSWORD=$3 docker exec -e KC_CLI_PASSWORD "$PREFIX-$name" "$KCADM" "${@:4}" \
    --no-config --server "$SERVER" --realm master --user "$user" < /dev/null
}
admin() { as "$1" admin "$KC_CLI_PASSWORD" "${@:2}"; }
admin_in() {
  docker exec -i -e KC_CLI_PASSWORD "$PREFIX-$1" "$KCADM" "${@:2}" --no-config --server "$SERVER" --realm master --user admin
}
# <expected text> <command…>: the command fails, and its output holds the text
refused_with() {
  local expected=$1 output
  shift
  if output=$("$@" 2>&1); then
    echo "succeeded:"
    printf '%s\n' "$output" | tail -n 3
    return 1
  fi
  grep -qF -- "$expected" <<< "$output" || { echo "failed without '$expected':"; printf '%s\n' "$output" | tail -n 3; return 1; }
}
# <name> <jq filter> <expected>: the master realm's value
master_is() {
  local value
  value=$(admin "$1" get realms/master 2> /dev/null | jq -c "$2") || { echo "get realms/master failed"; return 1; }
  [ "$value" = "$3" ] || { echo "$2 is $value, not $3"; return 1; }
}

# (i) a master realm Keycloak creates itself
printf '%s\n' KC_BOOTSTRAP_ADMIN_USERNAME=admin "KC_BOOTSTRAP_ADMIN_PASSWORD=$KC_CLI_PASSWORD" > "$work/created.env"
start created "$work/created.env"

import_file() { # <dir> <user profile JSON, or empty for the default one>
  mkdir -p "$1"
  jq -n --arg up "$2" '{
    realm: "master", enabled: true,
    displayName: "${FACT_NAME}", displayNameHtml: "${env.FACT_NAME}",
    verifyEmail: true, resetPasswordAllowed: "${FACT_TRUE}",
    smtpServer: { host: "${FACT_HOST}", port: "1025", from: "noreply@facts.test", auth: "true", user: "mailpit", password: "${FACT_SMTP_PASSWORD}", starttls: "false", ssl: "false" },
    users: [ { username: "${FACT_ADMIN_USERNAME}", enabled: true, email: "admin@facts.test", emailVerified: true,
               credentials: [ { type: "password", value: "${FACT_ADMIN_PASSWORD}", temporary: false } ], realmRoles: [ "admin" ] } ]
  } + (if $up == "" then {} else { components: { "org.keycloak.userprofile.UserProfileProvider": [ { providerId: "declarative-user-profile", subComponents: {}, config: { "kc.user.profile.config": [ $up ] } } ] } } end)' \
    > "$1/master-realm.json"
}
facts_env() { # <file> <smtp password> [extra lines…]
  printf '%s\n' FACT_NAME=fact-name FACT_TRUE=true FACT_HOST=fact-host FACT_ADMIN_USERNAME=admin \
    "FACT_ADMIN_PASSWORD=$KC_CLI_PASSWORD" "FACT_SMTP_PASSWORD=$2" "${@:3}" > "$1"
}

# (c) and (h) start at once: both are expected to stop
import_file "$work/default-profile" ""
facts_env "$work/bootstrap.env" smtp-fact KC_BOOTSTRAP_ADMIN_USERNAME=admin "KC_BOOTSTRAP_ADMIN_PASSWORD=$KC_CLI_PASSWORD"
start bootstrap "$work/bootstrap.env" "$work/default-profile"
facts_env "$work/quote.env" 'smtp"fact'
start quote "$work/quote.env" "$work/default-profile"
facts_env "$work/default.env" smtp-fact
start default "$work/default.env" "$work/default-profile"

check "(i) a throwaway Keycloak creating its own master realm is ready" ready created
check "(i) its accessTokenLifespan is 60" master_is created .accessTokenLifespan 60
check "(i) its displayName is Keycloak" master_is created .displayName '"Keycloak"'
created_profile=$(admin created get users/profile 2> /dev/null | jq -c 'with_entries(select(.value != null))')
not_required() {
  [ "$(jq -c '[.attributes[] | select(.name == "email" or .name == "firstName" or .name == "lastName") | .required] | unique' <<< "$created_profile")" = '[null]' ] \
    || { echo "$created_profile"; return 1; }
}
check "(i) its user profile requires neither email, firstName nor lastName" not_required

# the import of (a), (b), (d) to (g), with (i)'s user profile
import_file "$work/created-profile" "$created_profile"
start imported "$work/default.env" "$work/created-profile"

stopped_with() { # <name> <text of its log>
  local waited=0
  while [ -n "$(docker ps -q -f "name=^$PREFIX-$1$")" ] && [ "$waited" -lt 120 ]; do
    sleep 2
    waited=$((waited + 2))
  done
  [ -z "$(docker ps -q -f "name=^$PREFIX-$1$")" ] || { echo "still running after $waited s"; return 1; }
  docker logs "$PREFIX-$1" 2>&1 | grep -qF -- "$2" || { docker logs --tail 5 "$PREFIX-$1" 2>&1; return 1; }
}
check "(c) KC_BOOTSTRAP_ADMIN_* naming the imported user: Keycloak aborts its start" \
  stopped_with bootstrap "the temporary admin user account could not be created"
check "(h) a double quote in a value: the import fails, Keycloak doesn't start" \
  stopped_with quote "Failed to run import"

check "(b) with the default user profile, the import is ready" ready default
check "(b) its administrator's admin CLI login is refused (firstName, lastName required)" \
  refused_with "Account is not fully set up" admin default get realms/master --fields realm

check "(b) with (i)'s user profile, the import is ready" ready imported
check "(b) its administrator logs in with the admin CLI, verifyEmail on" admin imported get realms/master --fields realm
check "(a) \${FACT_NAME} took the environment's value" master_is imported .displayName '"fact-name"'
check "(a) \${env.FACT_NAME} didn't" master_is imported .displayNameHtml '"${env.FACT_NAME}"'
check "(a) the SMTP host too" master_is imported .smtpServer.host '"fact-host"'
check "(d) \"true\" became the boolean resetPasswordAllowed" master_is imported .resetPasswordAllowed true
verified_address() {
  [ "$(admin imported get users -q username=admin 2> /dev/null | jq -c '.[0] | [.email, .emailVerified]')" = '["admin@facts.test",true]' ]
}
check "(b) the administrator has its verified address" verified_address

# (e) the registration account, as registration-account.sh creates it
secret=$(openssl rand -hex 32)
create_account() {
  printf '{"clientId":"c4-infra-registration","publicClient":false,"serviceAccountsEnabled":true,"standardFlowEnabled":false,"implicitFlowEnabled":false,"directAccessGrantsEnabled":false,"secret":"%s"}' \
    "$secret" | admin_in imported create clients -f -
}
check "(e) the administrator creates the registration account" create_account
check "(e) and grants it create-realm" admin imported add-roles --uusername service-account-c4-infra-registration --rolename create-realm
account() {
  KC_CLI_CLIENT_SECRET=$secret docker exec -e KC_CLI_CLIENT_SECRET "$PREFIX-imported" sh -c '
    session=/dev/shm/c4-facts-$$.kcadm
    trap "rm -f $session" EXIT
    /opt/keycloak/bin/kcadm.sh config credentials --config "$session" --server "$1" --realm master --client c4-infra-registration > /dev/null || exit 1
    shift
    /opt/keycloak/bin/kcadm.sh "$@" --config "$session"' sh "$SERVER" "$@" < /dev/null
}
check "(e) the account creates a realm" account create realms -s realm=verif-facts -s enabled=true
check "(e) and manages it" account get realms/verif-facts/roles --fields name

# (g)
create_ops() { # <JSON of the user's address fields, or empty>
  printf '{"username":"ops","enabled":true%s,"credentials":[{"type":"password","value":"%s","temporary":false}]}' \
    "$1" "$KC_CLI_PASSWORD" | admin_in imported create users -f - > /dev/null \
    && admin imported add-roles --uusername ops --rolename admin
}
check "(g) an administrator ops without an address" create_ops ""
check "(g) logs in with the admin CLI, verifyEmail on" as imported ops "$KC_CLI_PASSWORD" get realms/master --fields realm
ops_id=$(admin imported get users -q username=ops --fields id 2> /dev/null | jq -r '.[0].id')
check "(g) its address set, not verified" admin imported update "users/$ops_id" -s email=ops@facts.test -s emailVerified=false
check "(g) its admin CLI login is refused" \
  refused_with "Account is not fully set up" as imported ops "$KC_CLI_PASSWORD" get realms/master --fields realm
# Keycloak 26.8.1 (intent 0013): the refused login stores no required action (26.7 stored
# VERIFY_EMAIL, which stayed once the address was verified, until removed by hand)
no_action() {
  [ "$(admin imported get "users/$ops_id" 2> /dev/null | jq -c .requiredActions)" = '[]' ]
}
check "(g) the refused login stored no required action" no_action
check "(g) its address then verified" admin imported update "users/$ops_id" -s emailVerified=true
check "(g) it logs in, nothing to remove" as imported ops "$KC_CLI_PASSWORD" get realms/master --fields realm

# (f)
sed -i 's/"displayName": "${FACT_NAME}"/"displayName": "another"/' "$work/created-profile/master-realm.json"
check "(f) the import file changed" grep -qF '"displayName": "another"' "$work/created-profile/master-realm.json"
docker restart "$PREFIX-imported" > /dev/null
check "(f) restarted, the Keycloak is ready" ready imported
check "(f) it skipped the import" grep -qF "Realm 'master' already exists. Import skipped" <(docker logs "$PREFIX-imported" 2>&1)
check "(f) the master realm is as it was" master_is imported .displayName '"fact-name"'
finish
