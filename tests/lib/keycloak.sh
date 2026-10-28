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
#
# and, for a throwaway Keycloak of the stack's image (on a file database, no published port):
#
#   kc_import_args           the arguments compose.yml gives keycloak-import (the dev model), one per
#                            line, for a throwaway: without --optimized, on --db=dev-file (intent 0012)
#   kc_throwaway_ready <container> [<s>]
#                            waits until it answers its readiness probe, at most <s> seconds (default
#                            240); returns 1, with its last log lines, when it stops or isn't by then
#
# and, for any Keycloak:
#
#   kc_curl <curl args…>     curl, silent, trusting the dev CA (certs/ca.crt), for the shared proxy's
#                            HTTPS
#   kc_claims <JWT>          the token's payload (JSON)
#   kc_features <Preview|Experimental> <log>
#                            the features of that kind the log's last start enabled, sorted, on one
#                            line ("a:v1,b:v1")

KC_CONTAINER=c4-infra.keycloak
KC_INFRA_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

# The value of KEY in .env, read as data (a simpler reader than the scripts', registry.sh's dotenv_value)
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

kc_import_args() {
  local command
  command=$( (cd "$KC_INFRA_DIR" && docker compose config --format json) \
    | jq -r '.services["keycloak-import"].command // [] | .[]' | tr -d '\r' | grep -vx -- --optimized) || true
  [ -n "$command" ] || { echo "kc_import_args: no keycloak-import command in the dev model" >&2; return 1; }
  printf '%s\n' "$command" --db=dev-file
}

kc_throwaway_ready() {
  local container=$1 limit=${2:-240} waited=0
  until MSYS_NO_PATHCONV=1 docker exec "$container" java -cp /opt/keycloak/healthcheck HealthCheck \
    http://localhost:9000/auth/health/ready > /dev/null 2>&1; do
    if [ -z "$(docker ps -q -f "name=^$container$")" ] || [ "$waited" -ge "$limit" ]; then
      echo "not ready ($waited s); its log:"
      docker logs --tail 5 "$container" 2>&1
      return 1
    fi
    sleep 2
    waited=$((waited + 2))
  done
}

kc_curl() {
  local ca=$KC_INFRA_DIR/certs/ca.crt
  ! command -v cygpath > /dev/null || ca=$(cygpath -w "$ca")
  curl --ssl-no-revoke --cacert "$ca" -s "$@"
}

kc_claims() {
  local payload
  payload=$(printf '%s' "$1" | cut -d. -f2 | tr '_-' '/+')
  while [ $((${#payload} % 4)) -ne 0 ]; do payload="${payload}="; done
  printf '%s' "$payload" | base64 -d
}

kc_features() {
  grep -oE "$1 features enabled: .*" <<< "$2" | tail -n 1 | sed 's/^[^:]*: //' | tr -d ' ' | tr ',' '\n' | LC_ALL=C sort | paste -sd, -
}
