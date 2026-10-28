#!/usr/bin/env bash
# 0033 (AC-10): what an application and the demo operator read names the backups' time limits: the
# file that sets them (/etc/c4-app/limits), each limit's name and its default (ITEM_TIMEOUT 1800,
# RESTORE_TIMEOUT 3600, NIGHTLY_TIMEOUT 7200), in README.md, c4-app's usage (read from demo/c4-app)
# and docs/demo-setup.md.
#
#   bash tests/0033-docs.sh
#
# covers: README.md demo/c4-app docs/demo-setup.md
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

TERMS=(/etc/c4-app/limits ITEM_TIMEOUT RESTORE_TIMEOUT NIGHTLY_TIMEOUT 1800 3600 7200)

names_every_term() { # <document> <its text>
  local term missing=()
  for term in "${TERMS[@]}"; do
    grep -qF -- "$term" <<< "$2" || missing+=("'$term'")
  done
  [ ${#missing[@]} -eq 0 ] || { echo "$1 doesn't name ${missing[*]}"; return 1; }
}

for doc in README.md docs/demo-setup.md; do
  check "$doc names ${TERMS[*]}" names_every_term "$doc" "$(cat "$doc")"
done
check "c4-app's usage names them" names_every_term "c4-app's usage" "$(sed -n '/^usage() {$/,/^}$/p' demo/c4-app)"
finish
