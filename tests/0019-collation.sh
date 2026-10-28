#!/usr/bin/env bash
# 0019: the tests sort in the C locale, whatever the workstation's: every sort command of tests/ (its
# scripts, tests/lib/, tests/run.sh) is `LC_ALL=C sort`. A sort in the workstation's collation (fr_FR
# puts .env after caddy/…, C before) compared with a list sorted in a container, or with a literal
# written in C order, fails there although both hold the same names (intent 0019). A bare one is named
# <file>:<line>.
#
# A command is a sort at a line's start or after | ; & ( { or $(, a command line run elsewhere
# (sh -c '…', eval '…') included; a jq program's sort is jq's (code points): its quoted program is left
# out.
#
#   bash tests/0019-collation.sh
#
# covers: tests/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

# the command's name from pieces, so that this file never holds one
command=so
command+=rt
bare() {
  local file number line found=""
  while IFS=: read -r file number line; do
    line=$(sed "s/jq[^'|]*'[^']*'/jq/g" <<< "$line")
    if grep -qE "(^|[|;&({]|\\\$\\()[[:space:]]*$command([[:space:]]|[)'\"]|$)" <<< "$line"; then
      found+="$file:$number"$'\n'
    fi
  done < <(git grep -nw "$command" -- 'tests/*.sh' 'tests/lib/*')
  [ -z "$found" ] || { printf '%s' "$found"; return 1; }
}
check "every $command of tests/ is LC_ALL=C $command (a bare one named)" bare
finish
