#!/usr/bin/env bash
# 0019: every sort command of tests/ is `LC_ALL=C sort`, so that a list sorted on a workstation
# whatever its locale compares with a container's or a literal in C order; a bare one, or one behind
# another prefix (LANG=C does not win over LC_ALL), is named <file>:<line>. A jq program's sort is
# jq's: the quoted program right after jq and its options is left out.
#
#   bash tests/0019-collation.sh
#
# covers: tests/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

# the command's name from pieces, so that this file never holds it
name=so
name+=rt
# a command's position: a line's start, after | ; & ( { ! $( ` or a quote opening a command line
# (sh -c, eval), or after a keyword or wrapper; any assignments in front
position="(^[^:]*:[0-9]+:|[|;&({!\`'\"]|\\\$\\(|(do|then|else|if|elif|while|until|xargs|env|time|command|nohup)[[:space:]])"
bare_pattern="$position[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*$name([^[:alnum:]_./-]|\$)"
bare() {
  local found
  # a grep that reads nothing would pass: the tests hold LC_ALL=C sorts
  git grep -q --untracked "LC_ALL=C $name" -- 'tests/*.sh' || { echo "no LC_ALL=C $name found: nothing was read"; return 1; }
  found=$(git grep -n --untracked -w "$name" -- 'tests/*.sh' 'tests/lib/*' \
    | sed -E "s/^([^:]*:[0-9]+:)[[:space:]]*#.*/\\1/; s/jq( +-[-[:alnum:]]+)* +'[^']*'/jq/g; s/LC_ALL=C +$name/LC_ALL_C_$name/g" \
    | grep -E "$bare_pattern" | cut -d: -f1,2)
  [ -z "$found" ] || { printf '%s\n' "$found"; return 1; }
}
check "every $name of tests/ is LC_ALL=C $name (a bare one named)" bare
finish
