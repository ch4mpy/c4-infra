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

# Each test's last duration, "<test> <microseconds>" per line, shared by the clone's worktrees: the
# stand-in lanes are split by it (spec 0022, PA-01)
durations_file=$(git rev-parse --git-common-dir)/c4-infra-test-durations
durations=()

recorded() { # <test>: its last duration in microseconds, 0 when none
  [ -f "$durations_file" ] || { echo 0; return; }
  awk -v test="$1" '$1 == test { took = $2 } END { print took + 0 }' "$durations_file"
}

record_durations() {
  { [ -f "$durations_file" ] && cat "$durations_file"; printf '%s\n' "${durations[@]}" | awk '{ print $2, $1 }'; } \
    | awk '{ took[$1] = $2 } END { for (test in took) print test, took[test] }' | sort > "$durations_file.new" \
    && mv "$durations_file.new" "$durations_file"
}

in_turn() { # every selected test, one after the other
  local test start took
  for test in "${selected[@]}"; do
    echo "== $test"
    start=$(micros)
    bash "$test" {SUITE_LOCK_FD}>&- || failed+=("$test")
    took=$(($(micros) - start))
    echo "-- $test: $(seconds "$took")"
    durations+=("$took $test")
  done
}

# A lane runs its tests (indexes of selected) one after the other, a stand-in lane with its own
# stand-in host. In $lanes: <i>.started when test i starts, its output in <i>.log, <i>.done
# ("<status> <microseconds>") when it ends, and lane<k>.pid the test running. The lane keeps the
# lock's pipe, its tests don't: a run killed with kill -9 holds the lock until its lanes end
lane() { # <k> <stand-in name, "" for none> <stand-in volume> <index…>
  local k=$1 name=$2 volume=$3 i start status
  shift 3
  for i in "$@"; do
    : > "$lanes/$i.started"
    start=$(micros)
    if [ -n "$name" ]; then
      STAND_IN_NAME=$name STAND_IN_VOLUME=$volume bash "${selected[$i]}" > "$lanes/$i.log" 2>&1 {SUITE_LOCK_FD}>&- &
    else
      bash "${selected[$i]}" > "$lanes/$i.log" 2>&1 {SUITE_LOCK_FD}>&- &
    fi
    echo $! > "$lanes/lane$k.pid"
    wait $!
    status=$?
    echo "$status $(($(micros) - start))" > "$lanes/$i.ending" && mv "$lanes/$i.ending" "$lanes/$i.done"
  done
}

# The stand-in tests in one or two lanes of their own (Docker's memory, spec PA-03), every other
# test in lane 1; only this shell prints, each test's output whole once it ends (PA-02)
in_lanes() {
  local i k others=() stand_ins=() d unknown=0 name volume
  local -a load=() members=() lane_names=() lane_volumes=() lane_of=() lane_pids=()
  local memory=${SUITE_DOCKER_MEMORY:-$(docker info --format '{{.MemTotal}}' 2> /dev/null || echo 0)}
  local stand_in_lanes=2
  for i in "${!selected[@]}"; do
    if [[ ${selected[$i]} == *.stand-in.sh ]]; then stand_ins+=("$i"); else others+=("$i"); fi
  done
  if [ "${memory:-0}" -lt 9663676416 ]; then
    stand_in_lanes=1
    echo "== Docker has $((${memory:-0} / 1073741824)) GiB, under the 10 GiB two stand-in lanes need (CLAUDE.md): one stand-in lane"
  fi
  [ ${#stand_ins[@]} -ge "$stand_in_lanes" ] || stand_in_lanes=${#stand_ins[@]}
  name=${STAND_IN_NAME:-c4-infra-stand-in}
  volume=${STAND_IN_VOLUME:-c4-infra-stand-in-docker}
  for ((k = 2; k < stand_in_lanes + 2; k++)); do
    load[k]=0
    if [ "$k" -eq 2 ]; then
      lane_names[k]=$name lane_volumes[k]=$volume
    else
      lane_names[k]=$name-$((k - 1)) lane_volumes[k]=${volume%-docker}-$((k - 1))-docker
    fi
  done
  # the longest first, each to the least loaded lane; the tests never run before, alternating
  while read -r d i; do
    if [ "$d" -eq 0 ]; then
      k=$((2 + unknown % stand_in_lanes))
      unknown=$((unknown + 1))
    else
      k=2
      [ "$stand_in_lanes" -eq 2 ] && [ "${load[3]}" -lt "${load[2]}" ] && k=3
    fi
    load[k]=$((load[k] + d))
    members[k]+=" $i"
    lane_of[i]="lane $k, stand-in ${lane_names[k]}"
  done < <(for i in "${stand_ins[@]}"; do echo "$(recorded "${selected[$i]}") $i"; done | sort -k1,1nr -k2,2n)
  for i in "${others[@]}"; do
    lane_of[i]="lane 1"
  done

  lanes=$(mktemp -d)
  trap 'interrupted' INT TERM
  if [ ${#others[@]} -gt 0 ]; then
    lane 1 "" "" "${others[@]}" &
    lane_pids+=($!)
  fi
  for ((k = 2; k < stand_in_lanes + 2; k++)); do
    lane "$k" "${lane_names[k]}" "${lane_volumes[k]}" ${members[k]} &
    lane_pids+=($!)
  done
  stand_in_hosts=("${lane_names[@]}")

  local -a announced=() printed=()
  local remaining=${#selected[@]} status took
  while [ "$remaining" -gt 0 ]; do
    for i in "${!selected[@]}"; do
      if [ -z "${announced[i]:-}" ] && [ -e "$lanes/$i.started" ]; then
        echo "== ${selected[$i]} started (${lane_of[i]}), its output in $lanes/$i.log"
        announced[i]=1
      fi
      if [ -z "${printed[i]:-}" ] && [ -e "$lanes/$i.done" ]; then
        read -r status took < "$lanes/$i.done"
        echo "== ${selected[$i]}"
        cat "$lanes/$i.log"
        echo "-- ${selected[$i]}: $(seconds "$took")"
        [ "$status" -eq 0 ] || failed+=("${selected[$i]}")
        durations+=("$took ${selected[$i]}")
        printed[i]=1
        remaining=$((remaining - 1))
      fi
    done
    [ "$remaining" -eq 0 ] || sleep 1
  done
  wait "${lane_pids[@]}"
  trap - INT TERM
  rm -rf "$lanes"
}

# Ctrl-C or TERM during lanes: no lane starts another test, their running tests get TERM, and their
# stand-in hosts are removed (their docker exec calls end with them)
interrupted() {
  local pid
  trap - INT TERM
  for pid in "${lane_pids[@]}"; do
    kill "$pid" 2> /dev/null
  done
  for pid in $(cat "$lanes"/lane*.pid 2> /dev/null); do
    kill "$pid" 2> /dev/null
  done
  [ ${#stand_in_hosts[@]} -eq 0 ] || docker rm -f "${stand_in_hosts[@]}" > /dev/null 2>&1
  rm -rf "$lanes"
  echo "interrupted: every lane stopped" >&2
  exit 130
}

has_stand_in() {
  local test
  for test in "${selected[@]}"; do
    [[ $test == *.stand-in.sh ]] && return 0
  done
  return 1
}

lanes=
lane_pids=()
stand_in_hosts=()
if [ ${#selected[@]} -gt 0 ]; then
  suite_lock_take || exit 1
  run_start=$(micros)
  if has_stand_in; then
    in_lanes
  else
    in_turn
  fi
  echo "total: $(seconds $(($(micros) - run_start))) for ${#selected[@]} test(s); the slowest:"
  printf '%s\n' "${durations[@]}" | sort -rn | head -n 5 | while read -r took test; do
    echo "  $(seconds "$took")  $test"
  done
  record_durations
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
