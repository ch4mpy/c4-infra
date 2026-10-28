#!/usr/bin/env bash
# 0003 (review round 1, 2026-10-22): up.sh reloads Caddy once compose is done; when Caddy refuses its
# configuration, it keeps serving the previous one, and up.sh says so and stops, exit 1, rather than
# restarting it (which would load the refused configuration: every site down).
#
#   bash tests/0003-up-reload.sh
#
# up.sh runs with fake getent and powershell.exe (tests/lib/stubs.sh, answering 127.0.0.1) and a fake
# docker of this test's, which logs each call and fails `caddy reload` with an error of Caddy's.
#
# covers: up.sh env.sh caddy/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/stubs.sh

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
stub_path "$work/stubs" getent powershell.exe
cat > "$work/stubs/docker" <<'EOF'
#!/usr/bin/env bash
echo "docker $*" >> "${STUB_LOG:?}"
case "$*" in
  *'caddy reload'*)
    echo 'Error: adapting config using caddyfile: stub-refused-directive, at /etc/caddy/Caddyfile:3' >&2
    exit 1
    ;;
esac
EOF
chmod +x "$work/stubs/docker"

: > "$work/docker.log"
STUB_LOG="$work/docker.log" STUB_ADDRESS=127.0.0.1 PATH="$work/stubs:$PATH" bash ./up.sh > "$work/out" 2> "$work/err"
status=$?

check "up.sh reached the reload (docker exec … caddy reload)" grep -qF 'caddy reload' "$work/docker.log"
check "a refused reload: up.sh exits 1 (exit $status)" test "$status" -eq 1
check "it prints Caddy's error" grep -qF 'stub-refused-directive' "$work/err"
check "it says the previous configuration keeps serving" grep -qF 'keeps serving its previous configuration' "$work/err"
check "it doesn't restart Caddy" eval '! grep -qF "docker restart" "$work/docker.log"'
# the registration account's admin CLI runs in c4-infra.keycloak (docker exec); up.sh's own look at
# Keycloak's image (docker inspect, intent 0013) comes before the reload
check "nothing runs after it (no registration account)" eval '! grep -E "^docker exec .*c4-infra\.keycloak" "$work/docker.log"'
finish
