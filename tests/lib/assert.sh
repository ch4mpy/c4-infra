# Checks for the tests of tests/: source it, call `check` for each assertion, then `finish`.
#
#   check <description> <command…>   runs the command: prints "ok - <description>", or
#                                     "KO - <description>" followed by the command's output
#   finish                           exits 1 when a check failed, 0 otherwise

failures=0

check() {
  local description=$1 output
  shift
  if output=$("$@" 2>&1); then
    echo "ok - $description"
  else
    echo "KO - $description"
    [ -z "$output" ] || printf '%s\n' "$output" | sed 's/^/     /'
    failures=$((failures + 1))
  fi
}

finish() {
  if [ "$failures" -gt 0 ]; then
    echo "$failures check(s) failed"
    exit 1
  fi
  echo "every check passed"
}
