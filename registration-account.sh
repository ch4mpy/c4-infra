#!/usr/bin/env bash
# The registration account: the service account of Keycloak's master realm that register-app.sh logs
# in as (KC_REGISTRATION_CLIENT_ID and KC_REGISTRATION_CLIENT_SECRET in .env). It may create realms
# (create-realm) and manage the registry's realms (every role of the master client <realm>-realm),
# nothing else: the master realm and the realms no application owns are out of its reach.
#
#   bash registration-account.sh ensure   the account as it must be: up.sh (dev) and demo/deploy.sh
#                                         (demo host) run it after each start. Logs in as the account
#                                         and probes every realm of the registry; only when the
#                                         account is missing, its secret isn't .env's, or a realm
#                                         that exists isn't granted to it, logs in as an administrator
#                                         to repair it: the bootstrap administrator of .env while it
#                                         works, else KC_SETUP_ADMIN_USERNAME and
#                                         KC_SETUP_ADMIN_PASSWORD from the environment, else, on a
#                                         terminal, the one it asks for; exit 1 when none logs in
#   bash registration-account.sh rotate   dev: a new secret into .env, then ensure (on the demo
#                                         host, the secret of the demo environment: docs/demo-setup.md)
#
# No secret goes on a command line: the admin CLI reads them from its environment (passed to
# docker exec by name), the client's JSON goes on stdin. The CLI's sessions live in the Keycloak
# container's /dev/shm (memory only, mode 600), removed on exit.
set -euo pipefail
# Git Bash would rewrite the container paths below (/opt/keycloak/..., /dev/shm/...) into Windows paths
export MSYS_NO_PATHCONV=1

INFRA_DIR=$(cd "$(dirname "$0")" && pwd)
source "$INFRA_DIR/registry.sh"

KEYCLOAK=c4-infra.keycloak
KCADM=/opt/keycloak/bin/kcadm.sh
SERVER=http://localhost:8080/auth
ACCOUNT_CONFIG=/dev/shm/c4-registration-$$.kcadm
ADMIN_CONFIG=/dev/shm/c4-registration-admin-$$.kcadm

usage() {
  echo "Usage: bash $0 ensure | rotate" >&2
  exit 2
}
[ $# -eq 1 ] || usage
case "$1" in
  ensure | rotate) command=$1 ;;
  *) usage ;;
esac

cleanup() {
  docker exec "$KEYCLOAK" rm -f "$ACCOUNT_CONFIG" "$ADMIN_CONFIG" < /dev/null > /dev/null 2>&1 || true
}
trap cleanup EXIT

# the admin CLI with a session file (account or admin); with -i, stdin is passed (the caller
# redirects it), else closed: a deployment runs this from a heredoc on ssh's stdin
kcadm_as() { # <config> [-i] <args…>
  local config=$1
  shift
  if [ "${1:-}" = -i ]; then
    shift
    docker exec -i "$KEYCLOAK" "$KCADM" "$@" --config "$config"
  else
    docker exec "$KEYCLOAK" "$KCADM" "$@" --config "$config" < /dev/null
  fi
}
account() { kcadm_as "$ACCOUNT_CONFIG" "$@"; }
admin() { kcadm_as "$ADMIN_CONFIG" "$@"; }

# Logs in as the account, the secret in KC_CLI_CLIENT_SECRET (passed by name); kcadm's output in
# $login_output
account_login() {
  login_output=$(KC_CLI_CLIENT_SECRET=$secret docker exec -e KC_CLI_CLIENT_SECRET "$KEYCLOAK" "$KCADM" \
    config credentials --config "$ACCOUNT_CONFIG" --server "$SERVER" --realm master --client "$client_id" \
    < /dev/null 2>&1)
}

admin_login() { # <user> <password>
  [ -n "$1" ] && [ -n "$2" ] || return 1
  KC_CLI_PASSWORD=$2 docker exec -e KC_CLI_PASSWORD "$KEYCLOAK" "$KCADM" \
    config credentials --config "$ADMIN_CONFIG" --server "$SERVER" --realm master --user "$1" \
    < /dev/null > /dev/null 2>&1
}

# What the account may do with a realm, as registrations ask it (get realms/<realm>/roles: `get
# realms/<realm>` answers a reduced view of any realm to whoever holds create-realm): 0 it manages
# it, 1 the realm is missing, 2 it exists and the account may not manage it, 3 another answer
# (printed on stderr)
probe() { # <realm>
  local output
  if output=$(account get "realms/$1/roles" --fields name 2>&1); then return 0; fi
  case "$output" in
    *"Resource not found"*) return 1 ;;
    *"HTTP 403"*) return 2 ;;
  esac
  printf '%s\n' "$output" | tail -n 3 >&2
  return 3
}

# The realms of the registry, one per line
registry_realms() {
  local lines number n app realms rest
  lines=$(registry_lines) || return 1
  while read -r number n app realms rest; do
    [ -n "$realms" ] && [ "$realms" != - ] || continue
    tr ',' '\n' <<< "$realms"
  done <<< "$lines"
}

# The realms of the registry that exist and the account may not manage, into $ungranted
probe_registry() {
  local realm status
  ungranted=()
  for realm in "${registry_realm_list[@]}"; do
    status=0
    probe "$realm" || status=$?
    case "$status" in
      0 | 1) ;;
      2) ungranted+=("$realm") ;;
      *)
        echo "Realm $realm: unexpected answer of Keycloak (above)" >&2
        exit 1
        ;;
    esac
  done
}

# An administrator of the master realm: the bootstrap one of .env while it works, else
# KC_SETUP_ADMIN_* from the environment, else the one a terminal gives
login_administrator() { # <what it is needed for>
  local user password bootstrap_password
  stack_env_read user KC_BOOTSTRAP_ADMIN_USERNAME
  stack_env_read bootstrap_password KC_BOOTSTRAP_ADMIN_PASSWORD
  if admin_login "$user" "$bootstrap_password"; then
    echo "Logged in as $user, the bootstrap administrator of .env, to $1"
    return 0
  fi
  if [ -n "${KC_SETUP_ADMIN_USERNAME:-}" ] && admin_login "$KC_SETUP_ADMIN_USERNAME" "${KC_SETUP_ADMIN_PASSWORD:-}"; then
    echo "Logged in as $KC_SETUP_ADMIN_USERNAME (KC_SETUP_ADMIN_USERNAME) to $1"
    return 0
  fi
  if [ -t 0 ]; then
    echo "The bootstrap administrator of .env doesn't log in (replaced, or its password changed): an administrator of Keycloak's master realm is needed to $1." >&2
    read -r -p "Administrator: " user
    read -r -s -p "Password: " password
    echo >&2
    if admin_login "$user" "$password"; then
      echo "Logged in as $user to $1"
      return 0
    fi
    echo "$user doesn't log in." >&2
  fi
  cat >&2 << EOF
No administrator of Keycloak's master realm could log in to $1: the bootstrap administrator of .env no longer works (replaced, or its password changed)${KC_SETUP_ADMIN_USERNAME:+, nor does $KC_SETUP_ADMIN_USERNAME (KC_SETUP_ADMIN_USERNAME)}.
  - In dev: run \`bash $INFRA_DIR/registration-account.sh ensure\` from a terminal: it asks for an administrator.
  - On the demo host: set the KC_SETUP_ADMIN_USERNAME and KC_SETUP_ADMIN_PASSWORD secrets of the demo environment, run the deployment once, then delete them (docs/demo-setup.md).
Registrations fail until then.
EOF
  exit 1
}

# The account's client, as it must be: confidential, its service account only (every other flow off),
# the secret of .env. Created, or updated in place; JSON on stdin, through a pipe (printf is a
# builtin: the secret is on no command line, nor in a temporary file).
representation() {
  printf '{"clientId":"%s","name":"c4-infra registrations","description":"register-app.sh: create-realm and the realms of the registry (registration-account.sh)","enabled":true,"publicClient":false,"clientAuthenticatorType":"client-secret","secret":"%s","serviceAccountsEnabled":true,"standardFlowEnabled":false,"implicitFlowEnabled":false,"directAccessGrantsEnabled":false,"attributes":{"oauth2.device.authorization.grant.enabled":"false","oidc.ciba.grant.enabled":"false"}}' \
    "$client_id" "$secret"
}
write_client() {
  local id
  id=$(admin get clients -q "clientId=$client_id" --fields id --format csv --noquotes | tr -d '\r')
  if [ -z "$id" ]; then
    representation | admin -i create clients -f - > /dev/null
    echo "Registration account $client_id: created"
  else
    representation | admin -i update "clients/$id" -f -
    echo "Registration account $client_id: its secret set to .env's"
  fi
}

grant_create_realm() {
  admin add-roles --uusername "service-account-$client_id" --rolename create-realm
}

grant_realm() { # <realm>: every role of the master client <realm>-realm
  local names name args=()
  names=$(admin get-roles --uusername "service-account-$client_id" --cclientid "$1-realm" --available \
    --fields name --format csv --noquotes | tr -d '\r')
  while IFS= read -r name; do
    [ -z "$name" ] || args+=(--rolename "$name")
  done <<< "$names"
  if [ ${#args[@]} -gt 0 ]; then
    admin add-roles --uusername "service-account-$client_id" --cclientid "$1-realm" "${args[@]}"
  fi
  echo "Registration account $client_id: realm $1 granted"
}

ensure() {
  stack_env_read client_id KC_REGISTRATION_CLIENT_ID
  stack_env_read secret KC_REGISTRATION_CLIENT_SECRET
  if [ -z "$client_id" ] || [ -z "$secret" ]; then
    echo "KC_REGISTRATION_CLIENT_ID and KC_REGISTRATION_CLIENT_SECRET must be in $INFRA_DIR/.env (env.sh writes them in dev, demo/write-env.sh on the demo host)" >&2
    exit 1
  fi
  if ! [[ $client_id =~ ^[a-z0-9][a-z0-9_-]*$ ]] || ! [[ $secret =~ ^[A-Za-z0-9._~+/=-]+$ ]]; then
    echo "KC_REGISTRATION_CLIENT_ID must be lowercase letters, digits, '_' and '-', and KC_REGISTRATION_CLIENT_SECRET letters, digits and ._~+/=- (openssl rand -hex 32)" >&2
    exit 1
  fi
  if ! registry_check; then
    echo "The registry is invalid (above): fix registry.txt; the registration account is left as it is." >&2
    exit 1
  fi
  mapfile -t registry_realm_list < <(registry_realms)

  local realm
  if account_login; then
    probe_registry
    if [ ${#ungranted[@]} -eq 0 ]; then
      echo "Registration account $client_id: up to date"
      return 0
    fi
    login_administrator "grant the registration account $client_id the realm(s) ${ungranted[*]}"
    grant_create_realm
  else
    login_administrator "create the registration account $client_id, or set its secret to .env's"
    write_client
    grant_create_realm
    if ! account_login; then
      printf '%s\n' "$login_output" | tail -n 3 >&2
      echo "Registration account $client_id: still doesn't log in after its repair (above)" >&2
      exit 1
    fi
    probe_registry
  fi
  for realm in "${ungranted[@]}"; do
    grant_realm "$realm"
  done
  # what registrations will see
  probe_registry
  if [ ${#ungranted[@]} -gt 0 ]; then
    echo "Registration account $client_id: still may not manage ${ungranted[*]} after the grant" >&2
    exit 1
  fi
  echo "Registration account $client_id: up to date"
}

# dev: a new secret into .env (the line replaced in place, the other lines as they were), then
# ensure sets it in Keycloak
rotate() {
  local infra_env new line found=false tmp
  stack_env_read infra_env INFRA_ENV
  if [ "$infra_env" != dev ]; then
    echo "rotate is for dev (INFRA_ENV=dev): on the demo host, the secret is the demo environment's KC_REGISTRATION_CLIENT_SECRET (docs/demo-setup.md, \"Rotating the registration secret\")" >&2
    exit 1
  fi
  new=$(openssl rand -hex 32)
  umask 077
  tmp=$(mktemp)
  {
    while IFS= read -r line || [ -n "$line" ]; do
      if [[ $line == KC_REGISTRATION_CLIENT_SECRET=* ]]; then
        printf '%s\n' "KC_REGISTRATION_CLIENT_SECRET=$new"
        found=true
      else
        printf '%s\n' "$line"
      fi
    done < "$INFRA_DIR/.env"
    $found || printf '%s\n' "KC_REGISTRATION_CLIENT_SECRET=$new"
  } > "$tmp"
  # into the same file: it keeps its owner and mode
  cat "$tmp" > "$INFRA_DIR/.env"
  rm -f "$tmp"
  echo "A new KC_REGISTRATION_CLIENT_SECRET is in .env"
  ensure
}

"$command"
