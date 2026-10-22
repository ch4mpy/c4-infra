# Keycloak for the tests of tests/: source it, then call
#
#   kc_admin <kcadm args…>   Keycloak's admin CLI in the container, as the bootstrap administrator of
#                            .env (read as data, as register-app.sh does), its password in the
#                            environment (KC_CLI_PASSWORD), never on a command line; stdin is not
#                            passed to the container
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
