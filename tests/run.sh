#!/usr/bin/env bash
# The repository's verification: `bash -n` on every shell script, then every test of tests/
# (tests/NNNN-*.sh). The *.stand-in.sh tests, which start a stand-in demo host, run with --all only.
# Needs the dev stack running (up.sh) and jq.
#
#   bash tests/run.sh [--all]
set -uo pipefail
cd "$(dirname "$0")/.."

all=false
case "${1:-}" in
  '') ;;
  --all) all=true ;;
  *)
    echo "Usage: $0 [--all]" >&2
    exit 2
    ;;
esac

failed=()

# the tracked scripts and the new ones, not those git ignores
while IFS= read -r script; do
  [ -f "$script" ] || continue
  bash -n "$script" || failed+=("bash -n $script")
done < <(git ls-files --cached --others --exclude-standard -- '*.sh')

for test in tests/[0-9][0-9][0-9][0-9]-*.sh; do
  [ -f "$test" ] || continue
  case "$test" in
    *.stand-in.sh)
      if ! $all; then
        echo "== $test: skipped (--all runs it)"
        continue
      fi
      ;;
  esac
  echo "== $test"
  bash "$test" || failed+=("$test")
done

if [ ${#failed[@]} -gt 0 ]; then
  echo "FAILED:"
  printf '  %s\n' "${failed[@]}"
  exit 1
fi
echo "verification passed"
