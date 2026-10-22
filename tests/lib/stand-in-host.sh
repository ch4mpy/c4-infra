#!/usr/bin/env bash
# A stand-in demo host for the tests: an Ubuntu container running its own Docker and sshd
# (tests/stand-in-host/), which receives exactly what the demo deployment sends and runs its
# commands. Source it, or run its self-test:
#
#   bash tests/lib/stand-in-host.sh selftest
#
#   stand_in_up                      builds the image and starts the stand-in (STAND_IN_FRESH=1: with
#                                    an empty Docker volume), then waits for its dockerd
#   stand_in_exec [-i] <command…>    runs the command in the stand-in, as root; -i passes stdin, which
#                                    the caller always redirects
#   stand_in_load_image <image>…     copies images of this machine into the stand-in's Docker
#   stand_in_send <dir>              sends the files of demo/deploy-files.txt into <dir>, as the
#                                    deployment does
#   stand_in_env <dir>               writes <dir>/.env with demo/write-env.sh, run inside the
#                                    stand-in (a Linux shell, as the workflow's runner), with a random
#                                    value for each secret `write-env.sh --required` names; then keeps
#                                    Let's Encrypt out (compose.no-acme.yml)
#   stand_in_down                    stops and removes the stand-in (its Docker volume stays: the
#                                    pulled images)
#
# The Docker volume c4-infra-stand-in-docker holds the stand-in's /var/lib/docker between runs.

STAND_IN_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
STAND_IN_NAME=c4-infra-stand-in
STAND_IN_IMAGE=c4-infra/stand-in-host
STAND_IN_VOLUME=c4-infra-stand-in-docker
STAND_IN_CADDY_IMAGE=caddy:2.11.4-alpine

# the docker CLI of Windows wants a Windows path for a build context
_stand_in_host_path() {
  if command -v cygpath > /dev/null; then cygpath -w "$1"; else printf '%s' "$1"; fi
}

stand_in_exec() {
  local options=()
  if [ "${1:-}" = -i ]; then
    options=(-i)
    shift
  fi
  MSYS_NO_PATHCONV=1 docker exec "${options[@]}" "$STAND_IN_NAME" "$@"
}

stand_in_up() {
  local waited=0
  docker build -q -t "$STAND_IN_IMAGE" "$(_stand_in_host_path "$STAND_IN_ROOT/tests/stand-in-host")" > /dev/null \
    || { echo "stand_in_up: the image doesn't build" >&2; return 1; }
  docker rm -f "$STAND_IN_NAME" > /dev/null 2>&1 || true
  if [ "${STAND_IN_FRESH:-0}" = 1 ]; then
    docker volume rm "$STAND_IN_VOLUME" > /dev/null 2>&1 || true
  fi
  MSYS_NO_PATHCONV=1 docker run -d --privileged --name "$STAND_IN_NAME" --hostname vps \
    -v "$STAND_IN_VOLUME:/var/lib/docker" "$STAND_IN_IMAGE" > /dev/null \
    || { echo "stand_in_up: the stand-in doesn't start" >&2; return 1; }
  until stand_in_exec docker info > /dev/null 2>&1; do
    if [ "$waited" -ge 60 ]; then
      echo "stand_in_up: no dockerd in the stand-in after 60 s; its log:" >&2
      stand_in_exec tail -n 20 /var/log/dockerd.log >&2
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
}

stand_in_load_image() {
  local image
  for image in "$@"; do
    docker save "$image" | stand_in_exec -i docker load -q > /dev/null \
      || { echo "stand_in_load_image: $image not loaded" >&2; return 1; }
  done
}

stand_in_send() { # <dir>
  stand_in_exec mkdir -p "$1" || return 1
  (cd "$STAND_IN_ROOT" && tar -cf - -T demo/deploy-files.txt) \
    | stand_in_exec -i tar -xf - --no-same-owner -C "$1"
}

# In a subshell: the generated secrets never reach the caller's environment
stand_in_env() ( # <dir>
  dir=$1
  options=()
  names=$(bash "$STAND_IN_ROOT/demo/write-env.sh" --required) || exit 1
  for name in $names; do
    if [[ $name == *_HASH ]]; then
      # a bcrypt hash of a random password; caddy reads the password on its stdin
      value=$(openssl rand -hex 16 | docker run --rm -i "$STAND_IN_CADDY_IMAGE" caddy hash-password) || exit 1
    else
      value=$(openssl rand -hex 16)
    fi
    export "$name=$value"
    # -e NAME, without a value: docker exec takes it from this environment, not the command line
    options+=(-e "$name")
  done
  export INFRA_HOST=infra.c4-soft.com KC_IMAGE=c4-infra/keycloak
  stand_in_exec -i sh -c 'cat > /tmp/write-env.sh' < "$STAND_IN_ROOT/demo/write-env.sh" || exit 1
  MSYS_NO_PATHCONV=1 docker exec "${options[@]}" -e INFRA_HOST -e KC_IMAGE "$STAND_IN_NAME" \
    bash /tmp/write-env.sh "$dir/.env" || exit 1
  stand_in_exec rm -f /tmp/write-env.sh
  stand_in_exec -i sh -c 'cat > "$1"' sh "$dir/compose.no-acme.yml" \
    < "$STAND_IN_ROOT/tests/stand-in-host/compose.no-acme.yml" || exit 1
  stand_in_exec sed -i 's/^COMPOSE_FILE=.*/&:compose.no-acme.yml/' "$dir/.env"
)

stand_in_down() {
  # docker stop: the entrypoint stops dockerd, which stops its containers
  docker stop -t 60 "$STAND_IN_NAME" > /dev/null 2>&1 || true
  docker rm -f "$STAND_IN_NAME" > /dev/null 2>&1 || true
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -uo pipefail
  case "${1:-}" in
    selftest)
      source "$STAND_IN_ROOT/tests/lib/assert.sh"
      trap stand_in_down EXIT
      check "the stand-in host starts, with its dockerd" stand_in_up
      check "docker info succeeds inside" stand_in_exec docker info
      check "docker compose is there" stand_in_exec docker compose version
      check "sshd -t succeeds inside" stand_in_exec /usr/sbin/sshd -t
      check "its host name is vps" test "$(stand_in_exec hostname | tr -d '\r')" = vps
      stand_in_down
      check "it stops" test -z "$(docker ps -aq -f "name=^$STAND_IN_NAME\$")"
      finish
      ;;
    *)
      echo "Usage: bash $0 selftest" >&2
      exit 2
      ;;
  esac
fi
