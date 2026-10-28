#!/usr/bin/env bash
# 0027 (AC-09): what an application and the demo operator read names the applications' backups: the
# declaration (c4-infra.backup), the commands (sudo c4-app backup, sudo c4-app restore), the
# directory (/var/backups/c4-apps/) and the nightly run (03:45), in README.md, c4-app's usage (read
# from demo/c4-app), docs/migration.md and docs/demo-setup.md; docs/migration.md no longer sends to
# an intent for a backup.
#
#   bash tests/0027-docs.sh
#
# covers: README.md demo/c4-app docs/migration.md docs/demo-setup.md
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

TERMS=(c4-infra.backup "sudo c4-app backup" "sudo c4-app restore" /var/backups/c4-apps/ 03:45)

names_every_term() { # <document> <its text>
  local term missing=()
  for term in "${TERMS[@]}"; do
    grep -qF -- "$term" <<< "$2" || missing+=("'$term'")
  done
  [ ${#missing[@]} -eq 0 ] || { echo "$1 doesn't name ${missing[*]}"; return 1; }
}

for doc in README.md docs/migration.md docs/demo-setup.md; do
  check "$doc names ${TERMS[*]}" names_every_term "$doc" "$(cat "$doc")"
done
check "c4-app's usage names them" names_every_term "c4-app's usage" "$(sed -n '/^usage() {$/,/^}$/p' demo/c4-app)"
check "docs/migration.md no longer says to open an intent for a backup" \
  eval '! grep -nF "open as an intent" docs/migration.md'
finish
