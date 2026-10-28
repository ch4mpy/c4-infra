#!/usr/bin/env bash
# 0011: up.sh tells a configuration Caddy refuses from a proxy it can't reach (AC-05), and runs on a
# fresh clone (AC-10):
#
#   - the reload refused while the admin API answers (the probe of compose.yml's healthcheck): "refuses
#     its configuration", Caddy's error printed;
#   - the reload refused and the admin API not answering, or docker exec failing (the container not
#     running): "isn't reachable", never "refuses";
#   - a copy of the tracked files (no .env, no certs/tls.crt) with a throwaway CA_DIR: up.sh reaches
#     docker compose up, or stops with a message; never a silent exit.
#
#   bash tests/0011-up.sh
#
# up.sh runs with fake getent and powershell.exe (tests/lib/stubs.sh, answering 127.0.0.1) and a fake
# docker of this test's, which logs each call; FAKE_RELOAD, FAKE_PROBE and FAKE_EXEC set what the
# proxy's container answers.
#
# covers: up.sh env.sh caddy/ certs/
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
if [ "${FAKE_EXEC:-}" = fails ] && [[ "$*" == "exec c4-infra.reverse-proxy "* ]]; then
  echo 'Error response from daemon: container 0011 is not running' >&2
  exit 1
fi
case "$*" in
  *'caddy reload'*)
    [ "${FAKE_RELOAD:-}" = refused ] || exit 0
    echo 'Error: adapting config using caddyfile: stub-refused-directive, at /etc/caddy/Caddyfile:3' >&2
    exit 1
    ;;
  *'2019/config/'*)
    [ "${FAKE_PROBE:-}" != fails ] || { echo 'wget: can'"'"'t connect to remote host (127.0.0.1): Connection refused' >&2; exit 1; }
    ;;
esac
EOF
chmod +x "$work/stubs/docker"

run_up() { # <dir of up.sh> [VAR=value…]: its exit status in $status, its output in $work/out and $work/err
  local dir=$1
  shift
  : > "$work/docker.log"
  env STUB_LOG="$work/docker.log" STUB_ADDRESS=127.0.0.1 PATH="$work/stubs:$PATH" "$@" \
    bash "$dir/up.sh" > "$work/out" 2> "$work/err" < /dev/null
  status=$?
}
said() { grep -qF -- "$1" "$work/err" || { echo "stderr:"; tail -n 8 "$work/err"; return 1; }; }
not_said() { ! grep -nF -- "$1" "$work/err"; }

run_up . FAKE_RELOAD=refused
check "AC-05: reload refused, the admin API answering: exit 1 (exit $status)" test "$status" -eq 1
check "AC-05: it prints Caddy's error" said 'stub-refused-directive'
check "AC-05: it says the proxy refuses its configuration" said 'The reverse proxy refuses its configuration'

run_up . FAKE_RELOAD=refused FAKE_PROBE=fails
check "AC-05: reload refused, the admin API not answering: exit 1 (exit $status)" test "$status" -eq 1
check "AC-05: it says the proxy isn't reachable" said "The reverse proxy isn't reachable"
check "AC-05: not that it refuses its configuration" not_said 'refuses its configuration'

run_up . FAKE_EXEC=fails
check "AC-05: docker exec failing (container not running): exit 1 (exit $status)" test "$status" -eq 1
check "AC-05: it says the proxy isn't reachable" said "The reverse proxy isn't reachable"
check "AC-05: not that it refuses its configuration" not_said 'refuses its configuration'

# AC-10: the tracked files only, as a fresh clone has them; its CA in a throwaway directory
mkdir -p "$work/clone" "$work/ca"
git ls-files -z | tar --null -T - -cf - | tar -xf - -C "$work/clone"
run_up "$work/clone" CA_DIR="$work/ca"
reached_up_or_said() {
  grep -q '^docker compose up -d --wait' "$work/docker.log" && return 0
  [ "$status" -ne 0 ] && [ -s "$work/err" ] && return 0
  echo "exit $status, no docker compose up, stderr: $(tail -n 5 "$work/err")"
  return 1
}
check "AC-10: a fresh clone (no certs/tls.crt): up.sh reaches docker compose up, or stops with a message" reached_up_or_said
check "AC-10: it creates certs/tls.crt" test -s "$work/clone/certs/tls.crt"
finish
