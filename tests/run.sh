#!/usr/bin/env bash
# The repository's verification: `bash -n` on every shell script, then every test of tests/
# (tests/NNNN-*.sh), each followed by its duration, the slowest listed at the end. The *.stand-in.sh
# tests, which start a stand-in demo host, and the *-facts.sh tests, which measure Keycloak's and
# Caddy's behaviour, run with --all only. Needs the dev stack running (up.sh) and jq.
#
#   bash tests/run.sh [--all] [--changed [<base>]]
#
#   --changed  only the tests the changed files concern (committed since <base>, origin/main or main
#              by default, staged, unstaged and untracked), as their `# covers:` lines declare them
#              (paths, a trailing / for a directory, or globs); a test is concerned by its own file
#              too. A change to tests/run.sh, tests/lib/ or a file no test declares runs every test
#              the run would run without --changed; the intent home's files (docs/intent/) concern
#              none. For intermediate checks: the full run stays the proof of a change.
#
# Every tracked script must be declared by a test: the run refuses one that isn't before any test.
# One run at a time per Docker: a run waits for another's end (tests/lib/suite-lock.sh).
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/suite-lock.sh

usage() {
  echo "Usage: $0 [--all] [--changed [<base>]]" >&2
  exit 2
}

all=false
changed=false
base=
while [ $# -gt 0 ]; do
  case "$1" in
    --all) all=true ;;
    --changed)
      changed=true
      if [ $# -gt 1 ] && [[ $2 != -* ]]; then
        base=$2
        shift
      fi
      ;;
    *) usage ;;
  esac
  shift
done

shopt -s nullglob
tests=(tests/[0-9][0-9][0-9][0-9]-*.sh)
shopt -u nullglob
declare -A covers=()
for test in "${tests[@]}"; do
  covers[$test]="$test $(sed -n 's/^# covers: //p' "$test" | tr '\n' ' ')"
done

matches() { # <file> <pattern>
  case "$2" in
    */) [[ $1 == "$2"* ]] ;;
    *) [[ $1 == $2 ]] ;;
  esac
}

concerns() { # <file> <test>: the test declares the file
  local pattern patterns
  read -ra patterns <<< "${covers[$2]}"
  for pattern in "${patterns[@]}"; do
    matches "$1" "$pattern" && return 0
  done
  return 1
}

declared() { # <file>: some test declares it
  local test
  for test in "${tests[@]}"; do
    concerns "$1" "$test" && return 0
  done
  return 1
}

# RQ-04: no tracked script without a test, before anything runs
uncovered=0
while IFS= read -r script; do
  declared "$script" && continue
  echo "uncovered: $script (no test declares it in a \"# covers:\" line)" >&2
  uncovered=1
done < <(git ls-files -- '*.sh' ':!tests/' demo/c4-app)
[ "$uncovered" -eq 0 ] || exit 1

failed=()

# the tracked scripts and the new ones, not those git ignores
while IFS= read -r script; do
  [ -f "$script" ] || continue
  bash -n "$script" || failed+=("bash -n $script")
done < <(git ls-files --cached --others --exclude-standard -- '*.sh')

every=true
files=
if $changed; then
  if [ -z "$base" ]; then
    base=origin/main
    git rev-parse -q --verify "$base^{commit}" > /dev/null || base=main
  fi
  committed=$(git diff --name-only "$base...HEAD") || usage
  files=$( {
    printf '%s\n' "$committed"
    git diff --name-only --cached
    git diff --name-only
    git ls-files --others --exclude-standard
  } | sed '/^$/d' | sort -u)
  every=false
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    if [[ $file == tests/run.sh || $file == tests/lib/* ]]; then
      echo "== --changed: $file is the suite's own: every test runs"
      every=true
    elif [[ $file != docs/intent/* ]] && ! declared "$file"; then
      echo "== --changed: no test declares $file: every test runs"
      every=true
    fi
  done <<< "$files"
fi

concerned() { # <test>: a changed file concerns it
  local file
  while IFS= read -r file; do
    [ -n "$file" ] && concerns "$file" "$1" && return 0
  done <<< "$files"
  return 1
}

# Why <test> doesn't run in this run: prints it, or nothing when it runs. The facts tests run with
# --all, and with --changed when a file they declare changes (spec PA-02), every test running or not
skipped() { # <test>
  if [[ $1 == *.stand-in.sh ]] && ! $all; then
    echo "--all runs it"
  elif $every && { $all || [[ $1 != *-facts.sh ]]; }; then
    return
  elif ! concerned "$1"; then
    if $every; then
      echo "--all runs it"
    else
      echo "not concerned by the change"
    fi
  fi
}

selected=()
for test in "${tests[@]}"; do
  reason=$(skipped "$test")
  if [ -n "$reason" ]; then
    echo "== $test: skipped ($reason)"
  else
    selected+=("$test")
  fi
done

micros() {
  echo "${EPOCHREALTIME/[.,]/}"
}

seconds() { # <microseconds>: in seconds, one decimal
  printf '%d.%d s' $(($1 / 1000000)) $(($1 / 100000 % 10))
}

durations=()
if [ ${#selected[@]} -gt 0 ]; then
  suite_lock_take || exit 1
  run_start=$(micros)
  for test in "${selected[@]}"; do
    echo "== $test"
    start=$(micros)
    bash "$test" {SUITE_LOCK_FD}>&- || failed+=("$test")
    took=$(($(micros) - start))
    echo "-- $test: $(seconds "$took")"
    durations+=("$took $test")
  done
  echo "total: $(seconds $(($(micros) - run_start))) for ${#selected[@]} test(s); the slowest:"
  printf '%s\n' "${durations[@]}" | sort -rn | head -n 5 | while read -r took test; do
    echo "  $(seconds "$took")  $test"
  done
fi

if [ ${#failed[@]} -gt 0 ]; then
  echo "FAILED:"
  printf '  %s\n' "${failed[@]}"
  exit 1
fi
if $changed; then
  echo "verification passed (--changed: ${#selected[@]} of ${#tests[@]} tests)"
else
  echo "verification passed"
fi
