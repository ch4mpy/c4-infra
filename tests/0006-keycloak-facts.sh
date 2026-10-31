#!/usr/bin/env bash
# 0006: the Keycloak behaviours the registration account relies on (RQ-01, RQ-02, RQ-04), checked in
# a throwaway Keycloak of the stack's image (start-dev on an in-memory database, no published port,
# its bootstrap password in an --env-file of a temporary directory):
#
#   (a) kcadm's `config credentials --client` reads the client secret from KC_CLI_CLIENT_SECRET (no
#       --secret on the command line) and logs in as the service account, into a config file of
#       /dev/shm, which the image's user may write;
#   (b) `--no-config --client`, with the secret in the environment only, doesn't authenticate (401);
#   (c) holding create-realm only, the account imports Faito's realm, whose service account keeps its
#       realm-management roles (query-users, view-users, manage-users);
#   (d) the probe registrations decide with: `get realms/<missing>/roles` says "Resource not found";
#       `get realms/<r>/roles` of a realm an administrator created answers 403, and so do its update
#       and its deletion; of a realm the account manages, it succeeds. A known Keycloak behaviour,
#       recorded here: `get realms/<r>` gives a reduced view (realm, displayName…, no id) of any
#       realm to an account holding create-realm, so it can't decide;
#   (e) the account deletes the realm it imported, and the administrator's realm once granted every
#       role of the master client <realm>-realm;
#   (f) it may not change the master realm (403).
#
#   bash tests/0006-keycloak-facts.sh
#
# Needs the image c4-infra/keycloak (up.sh builds it) and Faito's realm export (FAITO_DIR, default
# ../faito). The throwaway container is removed whatever happens.
#
# covers: keycloak/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/docker-preflight.sh
mapfile -t C4_LABELS < <(docker_labels c4-infra)

IMAGE=c4-infra/keycloak
NAME=c4-infra.0006-facts
FAITO_REALM=${FAITO_DIR:-../faito}/keycloak/import/faito-realm.json
CLIENT=c4-infra-registration
ACCOUNT=service-account-$CLIENT
CONFIG=/dev/shm/c4-registration-facts.kcadm
SERVER=http://localhost:8080/auth
KCADM=/opt/keycloak/bin/kcadm.sh
export MSYS_NO_PATHCONV=1

# the docker CLI of Windows wants a Windows path for a file it reads
host_path() {
  if command -v cygpath > /dev/null; then cygpath -w "$1"; else printf '%s' "$1"; fi
}

umask 077
work=$(mktemp -d)
trap 'docker rm -f -v "$NAME" > /dev/null 2>&1; rm -rf "$work"' EXIT

# The throwaway's secrets, in this shell's environment: docker exec takes them by name (-e NAME)
KC_CLI_PASSWORD=$(openssl rand -hex 16)
KC_CLI_CLIENT_SECRET=$(openssl rand -hex 32)
export KC_CLI_PASSWORD KC_CLI_CLIENT_SECRET
{
  echo "KC_BOOTSTRAP_ADMIN_USERNAME=admin"
  echo "KC_BOOTSTRAP_ADMIN_PASSWORD=$KC_CLI_PASSWORD"
} > "$work/kc.env"

# as the throwaway's bootstrap administrator; admin_in passes stdin, which the caller redirects
admin() {
  docker exec -e KC_CLI_PASSWORD "$NAME" "$KCADM" "$@" --no-config --server "$SERVER" --realm master --user admin < /dev/null
}
admin_in() {
  docker exec -i -e KC_CLI_PASSWORD "$NAME" "$KCADM" "$@" --no-config --server "$SERVER" --realm master --user admin
}
# as the registration account, once logged in (account_login)
account_login() {
  docker exec -e KC_CLI_CLIENT_SECRET "$NAME" "$KCADM" config credentials --config "$CONFIG" \
    --server "$SERVER" --realm master --client "$CLIENT" < /dev/null
}
account() {
  docker exec "$NAME" "$KCADM" "$@" --config "$CONFIG" < /dev/null
}
account_in() {
  docker exec -i "$NAME" "$KCADM" "$@" --config "$CONFIG"
}

# <expected text> <command…>: the command fails, and its output holds the text
refused_with() {
  local expected=$1 output
  shift
  if output=$("$@" 2>&1); then
    echo "succeeded:"
    printf '%s\n' "$output" | tail -n 5
    return 1
  fi
  grep -qF -- "$expected" <<< "$output" || { echo "failed without '$expected':"; printf '%s\n' "$output" | tail -n 5; return 1; }
  echo "# answer: $(printf '%s\n' "$output" | tail -n 1)" >&3
}
exec 3>&1

ready() {
  local waited=0
  until docker exec "$NAME" java -cp /opt/keycloak/healthcheck HealthCheck http://localhost:9000/auth/health/ready > /dev/null 2>&1; do
    if [ "$waited" -ge 240 ]; then
      echo "not ready after 240 s; its log:"
      docker logs --tail 20 "$NAME" 2>&1
      return 1
    fi
    sleep 2
    waited=$((waited + 2))
  done
}

check "Faito's realm export is there ($FAITO_REALM)" test -f "$FAITO_REALM"
docker rm -f -v "$NAME" > /dev/null 2>&1
check "a throwaway Keycloak of $IMAGE starts (start-dev, in-memory database)" \
  docker run "${C4_LABELS[@]}" -d --name "$NAME" --env-file "$(host_path "$work/kc.env")" "$IMAGE" start-dev --db=dev-mem
check "it is ready" ready

# The account, as registration-account.sh creates it: every flow off but the service account, its
# secret in JSON on stdin (printf is a builtin: on no command line), create-realm granted
create_account() {
  printf '{"clientId":"%s","publicClient":false,"serviceAccountsEnabled":true,"standardFlowEnabled":false,"implicitFlowEnabled":false,"directAccessGrantsEnabled":false,"secret":"%s"}' \
    "$CLIENT" "$KC_CLI_CLIENT_SECRET" | admin_in create clients -f -
}
check "the administrator creates the client $CLIENT, its secret on stdin" create_account
check "and grants its service account create-realm only" admin add-roles --uusername "$ACCOUNT" --rolename create-realm

# (a)
check "(a) config credentials --client logs in, the secret from KC_CLI_CLIENT_SECRET" account_login
config_mode=$(docker exec "$NAME" stat -c %a "$CONFIG" 2> /dev/null | tr -d '\r')
check "(a) into $CONFIG, mode 600 (it is ${config_mode:-missing})" test "$config_mode" = 600

# (b)
check "(b) --no-config --client with the secret in the environment only: 401" refused_with 401 \
  docker exec -e KC_CLI_CLIENT_SECRET "$NAME" "$KCADM" get realms/master --fields realm \
  --no-config --server "$SERVER" --realm master --client "$CLIENT"

# (c)
check "(c) holding create-realm only, the account imports Faito's realm" account_in create realms -f - < "$FAITO_REALM"
roles=$(admin get-roles -r faito --uusername service-account-faito-api --cclientid realm-management 2> "$work/roles.err" \
  | jq -r '.[].name' | LC_ALL=C sort | tr '\n' ' ')
for role in query-users view-users manage-users; do
  check "(c) service-account-faito-api keeps realm-management's $role (it has: ${roles:-none})" \
    grep -qw -- "$role" <<< "$roles"
done

check "(c) the account manages the realm it imported: get realms/faito/roles succeeds" \
  account get realms/faito/roles --fields name

# (d)
check "(d) get realms/verif-missing/roles: Resource not found" refused_with "Resource not found" \
  account get realms/verif-missing/roles --fields name
check "the administrator creates realm verif-admin-made" \
  admin create realms -s realm=verif-admin-made -s enabled=true -s displayName=before
check "(d) get realms/verif-admin-made/roles, the administrator's realm: 403" refused_with 403 \
  account get realms/verif-admin-made/roles --fields name
reduced_view() { # the known behaviour: a reduced view, with its name and display name, but no id
  local view
  view=$(account get realms/verif-admin-made) || { printf '%s\n' "$view"; return 1; }
  [ "$(jq -r '.realm + " " + .displayName + " " + (has("id") | tostring)' <<< "$view")" = "verif-admin-made before false" ] \
    || { printf '%s\n' "$view"; return 1; }
  echo "# answer: $(jq -c . <<< "$view")" >&3
}
check "(d) known behaviour: get realms/verif-admin-made gives the account a reduced view (realm, displayName, no id)" reduced_view
check "(d) update realms/verif-admin-made: 403" refused_with 403 \
  account update realms/verif-admin-made -s displayName=x
check "(d) delete realms/verif-admin-made: 403" refused_with 403 \
  account delete realms/verif-admin-made

# (e)
check "(e) the account deletes the realm it imported (faito)" account delete realms/faito
check "(e) realm faito is gone" refused_with "Resource not found" admin get realms/faito --fields realm
grant_realm() { # <realm>: every role of the master client <realm>-realm, to the account
  local names args=()
  names=$(admin get-roles --uusername "$ACCOUNT" --cclientid "$1-realm" --available | jq -r '.[].name') || return 1
  [ -n "$names" ] || { echo "no role available in $1-realm"; return 1; }
  while IFS= read -r name; do args+=(--rolename "$name"); done <<< "$names"
  admin add-roles --uusername "$ACCOUNT" --cclientid "$1-realm" "${args[@]}"
}
check "the administrator grants the account every role of verif-admin-made-realm" grant_realm verif-admin-made
check "(e) the account now manages realm verif-admin-made: get realms/verif-admin-made/roles succeeds" \
  account get realms/verif-admin-made/roles --fields name
check "(e) and deletes it" account delete realms/verif-admin-made
check "(e) realm verif-admin-made is gone" refused_with "Resource not found" admin get realms/verif-admin-made --fields realm

# (f)
check "(f) update realms/master: 403" refused_with 403 account update realms/master -s displayName=x
finish
