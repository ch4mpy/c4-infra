# Keycloak for the tests of tests/: source it, then call
#
#   kc_admin <kcadm args…>   Keycloak's admin CLI in the container, as the bootstrap administrator of
#                            .env (read as data, as register-app.sh does), its password in the
#                            environment (KC_CLI_PASSWORD), never on a command line; stdin is not
#                            passed to the container
#   kc_registration <kcadm args…>
#                            the same, as the registration account of .env (KC_REGISTRATION_CLIENT_ID),
#                            logged in as register-app.sh does: `config credentials --client`, its
#                            secret in KC_CLI_CLIENT_SECRET, the session in the container's /dev/shm,
#                            removed after the call
#   kc_secret_file           a new temporary file, mode 600, holding .env's registration secret on one
#                            line (for `grep -F -f`, which then prints nothing but a match); prints its
#                            path, the caller removes it
#   kc_started_at            when the container last started (State.StartedAt)
#   kc_wait_healthy [<s>]    waits until the container is healthy, at most <s> seconds (default
#                            300); returns 1, with its last status, when it isn't by then

KC_CONTAINER=c4-infra.keycloak
KC_INFRA_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

# The value of KEY in .env, read as data (register-app.sh's env_value)
_kc_env_value() {
  local line
  line=$(grep -m1 "^$1=" "$KC_INFRA_DIR/.env" || true)
  line=${line#*=}
  line=${line%$'\r'}
  printf '%s' "${line//\$\$/\$}"
}

kc_admin() {
  local user
  user=$(_kc_env_value KC_BOOTSTRAP_ADMIN_USERNAME)
  KC_CLI_PASSWORD=$(_kc_env_value KC_BOOTSTRAP_ADMIN_PASSWORD) MSYS_NO_PATHCONV=1 \
    docker exec -e KC_CLI_PASSWORD "$KC_CONTAINER" /opt/keycloak/bin/kcadm.sh "$@" \
    --no-config --server http://localhost:8080/auth --realm master --user "$user" < /dev/null
}

kc_registration() {
  KC_CLI_CLIENT_SECRET=$(_kc_env_value KC_REGISTRATION_CLIENT_SECRET) MSYS_NO_PATHCONV=1 \
    docker exec -e KC_CLI_CLIENT_SECRET "$KC_CONTAINER" sh -c '
      session=/dev/shm/c4-registration-test-$$.kcadm
      trap "rm -f $session" EXIT
      login=$(/opt/keycloak/bin/kcadm.sh config credentials --config "$session" \
        --server http://localhost:8080/auth --realm master --client "$1" 2>&1) \
        || { printf "%s\n" "$login" >&2; exit 1; }
      unset KC_CLI_CLIENT_SECRET
      shift
      /opt/keycloak/bin/kcadm.sh "$@" --config "$session"' \
    sh "$(_kc_env_value KC_REGISTRATION_CLIENT_ID)" "$@" < /dev/null
}

kc_secret_file() {
  local file secret
  secret=$(_kc_env_value KC_REGISTRATION_CLIENT_SECRET)
  [ -n "$secret" ] || { echo "kc_secret_file: no KC_REGISTRATION_CLIENT_SECRET in .env" >&2; return 1; }
  file=$(umask 077 && mktemp) || return 1
  printf '%s\n' "$secret" > "$file"
  printf '%s\n' "$file"
}

kc_started_at() {
  docker inspect -f '{{.State.StartedAt}}' "$KC_CONTAINER"
}

kc_wait_healthy() {
  local timeout=${1:-300} status
  local deadline=$((SECONDS + timeout))
  while :; do
    status=$(docker inspect -f '{{.State.Health.Status}}' "$KC_CONTAINER" 2> /dev/null)
    [ "$status" = healthy ] && return 0
    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "$KC_CONTAINER: ${status:-no status} after $timeout s"
      return 1
    fi
    sleep 1
  done
}
