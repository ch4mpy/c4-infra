#!/usr/bin/env bash
# 0011: the facts its fixes are built on, on this machine's Docker:
#
#   (a) `docker compose -p <project> down` with no compose file (run from an empty directory) removes
#       the project's containers and networks and keeps its volumes; on a project that doesn't exist,
#       it exits 0 (c4-app down, RQ-04);
#   (b) the same down, handed tests/fixtures/0011/down-hook.yml unchecked, runs its provider's
#       executable: AC-04's "no marker" means c4-app down handed compose no model (on Linux only:
#       Windows' compose runs no shell script as a provider);
#   (c) in a throwaway Caddy, the admin API probe of the proxy's healthcheck (compose.yml) answers
#       while a refused `caddy reload` fails, and fails once the container is stopped (up.sh, RQ-05).
#
#   bash tests/0011-facts.sh
#
# Its projects and container are removed whatever happens.
#
# covers: tests/fixtures/0011/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
export MSYS_NO_PATHCONV=1

PROJECT=c4-0011-facts
HOOK_PROJECT=c4-0011-hook
CADDY=c4-0011-caddy
IMAGE=caddy:2.11.4-alpine
work=$(mktemp -d)
cleanup() {
  docker rm -f "$CADDY" > /dev/null 2>&1
  (cd "$work/empty" && docker compose -p "$PROJECT" down -v > /dev/null 2>&1)
  docker volume rm "${PROJECT}_cache" > /dev/null 2>&1
  rm -rf "$work"
}
trap cleanup EXIT
mkdir -p "$work/empty"
# MSYS_NO_PATHCONV: the docker CLI of Windows gets the host paths in Windows' form from here
host_path() { if command -v cygpath > /dev/null; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

# (a) a project of a container, a network and a volume of its own, then down by name only
cat > "$work/compose.yml" <<EOF
services:
  gateway:
    image: $IMAGE
    command: [caddy, respond, --listen, ':7080', facts]
    networks: [internal]
    volumes: [cache:/cache]
networks:
  internal: {}
volumes:
  cache: {}
EOF
project_containers() { docker ps -aq --filter "label=com.docker.compose.project=$1" | tr -d '\r'; }
gone() { # <project>
  [ -z "$(project_containers "$1")" ] || { echo "containers of $1 left: $(project_containers "$1")"; return 1; }
  ! docker network inspect "${1}_internal" > /dev/null 2>&1 || { echo "${1}_internal left"; return 1; }
}
docker compose -p "$PROJECT" -f "$(host_path "$work/compose.yml")" up -d > "$work/up.log" 2>&1
check "(a) the project starts (a container, ${PROJECT}_internal, ${PROJECT}_cache)" test -n "$(project_containers "$PROJECT")"
(cd "$work/empty" && docker compose -p "$PROJECT" down --remove-orphans) > "$work/down.log" 2>&1
status=$?
check "(a) down with no compose file exits 0 (exit $status)" test "$status" -eq 0
check "(a) its containers and network are gone" gone "$PROJECT"
check "(a) its volume stays" docker volume inspect "${PROJECT}_cache"
(cd "$work/empty" && docker compose -p c4-0011-no-such-project down --remove-orphans) > "$work/down-none.log" 2>&1
status=$?
check "(a) on a project that doesn't exist, it exits 0 (exit $status)" test "$status" -eq 0

# (b) down handed the hook's model: compose runs the provider's executable
if command -v cygpath > /dev/null; then
  echo "# (b) not measured under Git Bash: Windows' compose runs no shell script as a provider"
else
  cp tests/fixtures/0011/hook.sh "$work/hook.sh"
  sed "s#/var/lib/c4-apps/faito/hook.sh#$work/hook.sh#" tests/fixtures/0011/down-hook.yml > "$work/down-hook.yml"
  docker compose -p "$HOOK_PROJECT" -f "$work/down-hook.yml" down > "$work/hook.log" 2>&1
  hook_ran() { [ -f "$work/hook-ran" ] || { echo "compose said:"; tail -n 5 "$work/hook.log"; return 1; }; }
  check "(b) down of down-hook.yml, unchecked, runs its provider (the marker hook-ran)" hook_ran
fi

# (c) the admin API probe of compose.yml's healthcheck, against a refused reload, then a stopped container
probe() { docker exec "$CADDY" wget -q -O /dev/null http://127.0.0.1:2019/config/; }
answers_soon() {
  local i
  for ((i = 0; i < 20; i++)); do
    probe 2> /dev/null && return 0
    sleep 0.5
  done
  probe
}
docker run -d --name "$CADDY" "$IMAGE" > /dev/null
check "(c) a throwaway Caddy's admin API answers the probe" answers_soon
docker exec "$CADDY" sh -c 'printf ":80 {\n\tstub-refused-directive\n}\n" > /tmp/refused.Caddyfile'
docker exec "$CADDY" caddy reload --config /tmp/refused.Caddyfile --adapter caddyfile > "$work/reload.log" 2>&1
status=$?
check "(c) caddy reload of a refused configuration fails (exit $status)" test "$status" -ne 0
check "(c) while the probe still answers" probe
docker stop "$CADDY" > /dev/null
check "(c) once the container is stopped, the probe fails" eval '! probe'
finish
