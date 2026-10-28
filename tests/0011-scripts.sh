#!/usr/bin/env bash
# 0011: two stack scripts that misreported their errors (on the workstation):
#
#   networks   AC-06: networks.sh compose-file with no daemon answering and no compose.apps.yml, in a
#              Linux container (bash:5.2, which has flock) while another process holds the lock on the
#              stack's directory: it waits, writes nothing meanwhile, then writes "services: {}" once
#              released, through a temporary file renamed into place (none left beside it);
#   dotenv     AC-07: registry.sh's dotenv_value on an .env grep can't read (a fake grep exiting 2, as
#              for a file without read permission; Git Bash has no such file): it fails, naming the
#              file; a missing key still reads as empty. AC-08: the six values of
#              tests/fixtures/0011/six-values.env, read by dotenv_value and by docker compose config,
#              are alike (a guard: no fix, spec PA-02).
#
#   bash tests/0011-scripts.sh [networks] [dotenv]      (both by default)
#
# covers: networks.sh registry.sh registry.txt tests/fixtures/0011/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

host_path() { if command -v cygpath > /dev/null; then cygpath -w "$1"; else printf "%s" "$1"; fi; }

part_networks() {
  local scratch=$work/networks
  mkdir -p "$scratch/stubs"
  cp networks.sh registry.sh registry.txt "$scratch/"
  printf 'INFRA_ENV=dev\n' > "$scratch/.env"
  # no daemon answering
  printf '#!/usr/bin/env bash\nexit 1\n' > "$scratch/stubs/docker"
  chmod +x "$scratch/stubs/docker"
  MSYS_NO_PATHCONV=1 docker run --rm --user 1000 -v "$(host_path "$scratch"):/w" bash:5.2 bash -c '
    export PATH=/w/stubs:$PATH
    flock /w sleep 5 &
    sleep 1
    timeout 2 bash /w/networks.sh compose-file; echo "while held: exit $?"
    [ -f /w/compose.apps.yml ] && echo "while held: written" || echo "while held: not written"
    wait
    bash /w/networks.sh compose-file; echo "released: exit $?"' > "$work/flock.log" 2>&1
  check "AC-06: no daemon, the lock held: compose-file waits (stopped by timeout 2 s: 124, busybox's 143)" \
    grep -qxE 'while held: exit (124|143)' "$work/flock.log"
  check "AC-06: and writes nothing meanwhile" grep -qx 'while held: not written' "$work/flock.log"
  check "AC-06: once released, it exits 0" grep -qx 'released: exit 0' "$work/flock.log"
  check "AC-06: the file is \"services: {}\"" grep -qx 'services: {}' "$scratch/compose.apps.yml"
  check "AC-06: no temporary file left beside it" \
    eval '[ -z "$(find "$scratch" -maxdepth 1 -name "compose.apps.yml.*")" ]'
}

part_dotenv() {
  local env=$work/dotenv.env value status
  printf 'PRESENT=yes\n' > "$env"
  mkdir -p "$work/fake-grep"
  # its message names no file: the one naming it must be dotenv_value's
  printf '#!/usr/bin/env bash\necho "grep: Permission denied" >&2\nexit 2\n' > "$work/fake-grep/grep"
  chmod +x "$work/fake-grep/grep"
  # shellcheck source=../registry.sh
  source ./registry.sh
  value=$(PATH="$work/fake-grep:$PATH" dotenv_value "$env" PRESENT 2> "$work/dotenv.err")
  status=$?
  check "AC-07: an .env grep can't read: dotenv_value fails (exit $status)" test "$status" -ne 0
  check "AC-07: naming the file" grep -qF -- "$env" "$work/dotenv.err"
  check "AC-07: and reads no value" test -z "$value"
  value=$(dotenv_value "$env" MISSING)
  status=$?
  check "AC-07: a missing key still reads as empty, exit 0 (exit $status, '$value')" \
    eval '[ "$status" -eq 0 ] && [ -z "$value" ]'

  # AC-08: compose interpolates each key from the file; dotenv_value reads the same file
  local compose dotenv key
  {
    printf 'services:\n  s:\n    image: busybox\n    environment:\n'
    for key in A B C D E F; do printf '      %s: ${%s}\n' "$key" "$key"; done
  } > "$work/six.yml"
  compose=$(docker compose --env-file tests/fixtures/0011/six-values.env -f "$work/six.yml" config --format json \
    | jq -r '.services.s.environment | to_entries[] | "\(.key)=[\(.value)]"')
  dotenv=$(for key in A B C D E F; do printf '%s=[%s]\n' "$key" "$(dotenv_value tests/fixtures/0011/six-values.env "$key")"; done)
  alike() { [ -n "$compose" ] && [ "$compose" = "$dotenv" ] || { echo "compose: $compose"; echo "dotenv_value: $dotenv"; return 1; }; }
  check "AC-08: the six values, read by dotenv_value and by docker compose config, are alike" alike
}

[ $# -gt 0 ] || set -- networks dotenv
for part in "$@"; do
  case "$part" in
    networks | dotenv)
      echo "# $part"
      "part_$part"
      ;;
    *)
      echo "Unknown part: $part (networks or dotenv)" >&2
      exit 2
      ;;
  esac
done
finish
