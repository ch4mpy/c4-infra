#!/usr/bin/env bash
# 0017: tests/run.sh's durations, selection, coverage check and lock (AC-01 to AC-06, AC-08, PA-02),
# on a throwaway git repository: a copy of tests/run.sh and tests/lib/, the scripts a.sh, b.sh, c.sh
# and dir/d.sh, and four fake tests that log their start and end and sleep a little: 0001-alpha
# (covers a.sh, 0.9 s), 0002-beta (b.sh dir/, 0.3 s), 0003-gamma-facts (c.sh glob/*.conf, 0.6 s),
# 0004-delta.stand-in (a.sh, 0.05 s). Their runs take a lock of their own (SUITE_LOCK_NAME).
#
#   bash tests/0017-run.sh
#
# The lock's facts (0017's step 1, Linux with Docker Desktop; not measured under Git Bash): a
# container fed by a pipe from the run is removed within a second when the run exits, fails, gets
# SIGINT or is killed with kill -9, its test still running; a second `docker run --name` of it fails
# ("is already in use") while it lives.
#
# covers: tests/run.sh tests/lib/suite-lock.sh
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

work=$(mktemp -d)
repo=$work/repo
other=$work/other
export SUITE_LOCK_NAME=c4-infra.suite-lock-0017-$$
export STAND_IN_NAME=c4-infra-stand-in-0017-$$ STAND_IN_VOLUME=c4-infra-stand-in-0017-$$-docker
cleanup() { # the tests of the runs killed or interrupted below, and their sleep
  local pid
  for pid in $(cat "$work"/pid-kill-9-* "$work"/pid-interrupted-* 2> /dev/null); do
    kill "$pid" 2> /dev/null
  done
  docker rm -f "$SUITE_LOCK_NAME" > /dev/null 2>&1
  rm -rf "$work"
}
trap cleanup EXIT

git_() {
  git -C "$repo" -c user.name=0017 -c user.email=0017@verif.test "$@"
}

# <name> <seconds> <covers…>; $work/sleep-<run>-<name> changes its sleep, $work/fail-<name> fails it.
# Its pid and its sleep's go to $work/pid-<run>-<name>
fake_test() {
  local name=$1 seconds=$2
  shift 2
  cat > "$repo/tests/$name.sh" << EOF
#!/usr/bin/env bash
# a fake test of tests/0017-run.sh
# covers: $*
echo \$\$ > "$work/pid-\${RUN_ID:-run}-$name"
echo "\${RUN_ID:-run} $name start \$EPOCHREALTIME" >> "$work/order.log"
sleep "\$(cat "$work/sleep-\${RUN_ID:-run}-$name" 2> /dev/null || echo $seconds)" &
echo \$! >> "$work/pid-\${RUN_ID:-run}-$name"
wait \$!
echo "\${RUN_ID:-run} $name end \$EPOCHREALTIME" >> "$work/order.log"
[ ! -e "$work/fail-$name" ]
EOF
}

mkdir -p "$repo/tests/lib" "$repo/dir"
cp tests/run.sh "$repo/tests/"
cp tests/lib/*.sh "$repo/tests/lib/"
fake_test 0001-alpha 0.9 a.sh
fake_test 0002-beta 0.3 b.sh dir/
fake_test 0003-gamma-facts 0.6 c.sh 'glob/*.conf'
fake_test 0004-delta.stand-in 0.05 a.sh
for script in a.sh b.sh c.sh dir/d.sh; do
  echo true > "$repo/$script"
done
mkdir -p "$repo/glob"
echo a > "$repo/glob/a.conf"
git_ init -q -b main
git_ add -A
git_ commit -q -m base

suite() { # <log> <option…>: tests/run.sh in the repository, its status in $status
  local log=$1
  shift
  bash "$repo/tests/run.sh" "$@" > "$work/$log" 2>&1
  status=$?
}

ran() { # <log>: the tests it ran, in order, by name
  sed -n 's|^== tests/\([^ :]*\)\.sh$|\1|p' "$work/$1" | tr '\n' ' ' | sed 's/ $//'
}

ran_exactly() { # <log> <names>
  [ "$(ran "$1")" = "$2" ] || { echo "ran: $(ran "$1")"; cat "$work/$1"; return 1; }
}

# A run with a stand-in test prints each block as its test ends (0022's lanes): the set of tests,
# and the order of those outside the stand-in lanes
ran_set() { # <log> <names, sorted>
  [ "$(ran "$1" | tr ' ' '\n' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')" = "$2" ] || { cat "$work/$1"; return 1; }
}

ran_others_in_order() { # <log> <names>
  [ "$(ran "$1" | tr ' ' '\n' | grep -v '\.stand-in$' | tr '\n' ' ' | sed 's/ $//')" = "$2" ] \
    || { cat "$work/$1"; return 1; }
}

skipped_for() { # <log> <name> <reason>
  grep -qxF "== tests/$2.sh: skipped ($3)" "$work/$1" || { cat "$work/$1"; return 1; }
}

passed() { # <log>
  [ "$status" -eq 0 ] || { echo "exit $status"; cat "$work/$1"; return 1; }
}

slowest_order() { # <log> <names>: the slowest list, by name
  local order
  order=$(sed -n '/^total: .*the slowest:$/,$p' "$work/$1" | sed -n 's|^  [0-9.]* s  tests/\(.*\)\.sh$|\1|p' \
    | tr '\n' ' ' | sed 's/ $//')
  [ "$order" = "$2" ] || { echo "slowest: $order"; cat "$work/$1"; return 1; }
}

has_durations() { # <log>: a duration line after each test it ran
  local name
  for name in $(ran "$1"); do
    grep -qE "^-- tests/$name\.sh: [0-9]+\.[0-9] s$" "$work/$1" || { echo "no duration for $name"; return 1; }
  done
  grep -qE '^total: [0-9]+\.[0-9] s for [0-9]+ test\(s\); the slowest:$' "$work/$1" || { echo "no total"; return 1; }
}

# AC-05, AC-01: the plain run and --all
suite plain.log
check "plain: passes" passed plain.log
check "plain: runs the tests but the stand-in and the facts ones, in order" ran_exactly plain.log "0001-alpha 0002-beta"
check "plain: the facts test skipped" skipped_for plain.log 0003-gamma-facts "--all runs it"
check "plain: the stand-in test skipped" skipped_for plain.log 0004-delta.stand-in "--all runs it"
check "AC-01: each test's duration, then the total" has_durations plain.log
check "AC-01: the slowest first" slowest_order plain.log "0001-alpha 0002-beta"
check "plain: its last line" test "$(tail -n 1 "$work/plain.log")" = "verification passed"
suite all.log --all
check "--all: runs every test" ran_set all.log "0001-alpha 0002-beta 0003-gamma-facts 0004-delta.stand-in"
check "--all: those outside the stand-in lanes in order" ran_others_in_order all.log "0001-alpha 0002-beta 0003-gamma-facts"
check "AC-01: --all, the slowest first" slowest_order all.log "0001-alpha 0003-gamma-facts 0002-beta 0004-delta.stand-in"

touch "$work/fail-0002-beta"
suite failed.log
rm "$work/fail-0002-beta"
check "a failed test: exit 1" test "$status" -eq 1
check "a failed test: listed" grep -qxF "  tests/0002-beta.sh" "$work/failed.log"

# AC-04
echo true > "$repo/e.sh"
git_ add e.sh
suite uncovered.log
check "AC-04: an uncovered script: exit 1" test "$status" -eq 1
check "AC-04: named" grep -qF 'uncovered: e.sh' "$work/uncovered.log"
check "AC-04: before any test" test -z "$(ran uncovered.log)"
git_ rm -q --cached e.sh
rm "$repo/e.sh"

# AC-02: unstaged, committed and untracked changes
echo '# changed' >> "$repo/a.sh"
suite unstaged.log --changed
check "AC-02: a.sh unstaged: the tests declaring it" ran_exactly unstaged.log "0001-alpha"
check "AC-02: the others skipped, not concerned" skipped_for unstaged.log 0002-beta "not concerned by the change"
check "AC-02: the stand-in one declaring it, for --all" skipped_for unstaged.log 0004-delta.stand-in "--all runs it"
check "AC-02: its last line says so" test "$(tail -n 1 "$work/unstaged.log")" = "verification passed (--changed: 1 of 4 tests)"
suite unstaged-all.log --all --changed
check "AC-02: with --all, the stand-in one too" ran_set unstaged-all.log "0001-alpha 0004-delta.stand-in"
git_ checkout -q a.sh

git_ switch -q -c work
echo '# changed' >> "$repo/b.sh"
git_ commit -q -am 'b.sh changed'
suite committed.log --changed
check "AC-02: b.sh committed since main: the test declaring it" ran_exactly committed.log "0002-beta"
suite base.log --changed HEAD
check "AC-02: with HEAD as the base, nothing runs" ran_exactly base.log ""
check "AC-02: and every test says why" skipped_for base.log 0001-alpha "not concerned by the change"
git_ switch -q main

echo true > "$repo/dir/new.sh"
suite untracked.log --changed
check "AC-02: dir/new.sh untracked: the test declaring dir/" ran_exactly untracked.log "0002-beta"
rm "$repo/dir/new.sh"

# PA-02: a facts test runs with --changed when what it declares changes
echo '# changed' >> "$repo/c.sh"
suite facts.log --changed
check "PA-02: c.sh changed: its facts test runs" ran_exactly facts.log "0003-gamma-facts"
echo notes > "$repo/notes.txt"
suite facts-every.log --changed
check "PA-02: with every test running (notes.txt), the facts test c.sh concerns too" \
  ran_exactly facts-every.log "0001-alpha 0002-beta 0003-gamma-facts"
rm "$repo/notes.txt"
git_ checkout -q c.sh

# a glob is matched as a pattern, never expanded against the working tree (where glob/*.conf is
# glob/a.conf only)
mkdir -p "$repo/glob/sub"
echo b > "$repo/glob/sub/new.conf"
suite glob.log --changed
check "a covers glob (glob/*.conf) matches glob/sub/new.conf" ran_exactly glob.log "0003-gamma-facts"
rm -r "$repo/glob/sub"

# AC-03: the suite's own files, and a file no test declares
echo '# changed' >> "$repo/tests/lib/assert.sh"
suite lib.log --changed
check "AC-03: tests/lib/ changed: the plain run's tests" ran_exactly lib.log "0001-alpha 0002-beta"
check "AC-03: saying why" grep -qxF "== --changed: tests/lib/assert.sh is the suite's own: every test runs" "$work/lib.log"
git_ checkout -q tests/lib/assert.sh
echo notes > "$repo/notes.txt"
suite undeclared.log --changed
check "AC-03: notes.txt, which no test declares: the plain run's tests" ran_exactly undeclared.log "0001-alpha 0002-beta"
check "AC-03: saying why" grep -qxF "== --changed: no test declares notes.txt: every test runs" "$work/undeclared.log"
rm "$repo/notes.txt"

# AC-08: the intent home's files concern no test
mkdir -p "$repo/docs/intent/0099-verif"
echo plan > "$repo/docs/intent/0099-verif/plan.md"
suite intent.log --changed
check "AC-08: docs/intent/ only: no test runs" ran_exactly intent.log ""
check "AC-08: each one skipped, not concerned" skipped_for intent.log 0002-beta "not concerned by the change"
echo '# changed' >> "$repo/a.sh"
suite intent-and-a.log --changed
check "AC-08: with a.sh too: the tests declaring a.sh only" ran_exactly intent-and-a.log "0001-alpha"
git_ checkout -q a.sh
rm -rf "$repo/docs"

# AC-06: the lock. The waiting run is in another worktree; a run is started as a terminal starts it
# (SIGINT at its default, a process group of its own) so that Ctrl-C can be sent to it
git_ worktree add -q --detach "$other" main
started() { # <run>: its first test started
  local i
  for ((i = 0; i < 100; i++)); do
    grep -q "^$1 0001-alpha start" "$work/order.log" 2> /dev/null && return 0
    sleep 0.2
  done
  echo "$1 never started"
  return 1
}
as_terminal() { # <run> <log> <run.sh>: in the background, its pid in $holder
  RUN_ID=$1 perl -e '$SIG{INT} = "DEFAULT"; setpgrp(0, 0); exec @ARGV' bash "$3" > "$work/$2" 2>&1 &
  holder=$!
}
first_start_after_last_end() { # <second run> <first run>
  awk -v b="$1" -v a="$2" '
    $1 == a && $3 == "end" && $4 > last { last = $4 }
    $1 == b && $3 == "start" && (first == "" || $4 < first) { first = $4 }
    END { if (first == "" || first <= last) { print "first start of " b ": " first ", last end of " a ": " last; exit 1 } }
  ' "$work/order.log"
}
waited_for() { # <log> <worktree>
  grep -qE "^waiting for the run of $2, started [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{8}$" "$work/$1" \
    || { cat "$work/$1"; return 1; }
}
starts_within() { # <log> <seconds>: the run took less than that to start its first test
  [ "$took" -lt "$2" ] || { echo "took $took s"; cat "$work/$1"; return 1; }
}

echo 3 > "$work/sleep-A-0001-alpha"
as_terminal A a.log "$repo/tests/run.sh"
check "AC-06: the first run holds the lock" started A
RUN_ID=B bash "$other/tests/run.sh" > "$work/b.log" 2>&1
status=$?
wait "$holder"
check "AC-06: the second run says which run holds the stack" waited_for b.log "$repo"
check "AC-06: and starts no test before the first run's end" first_start_after_last_end B A
check "AC-06: then runs" passed b.log

for ending in kill-9 interrupted; do
  echo 30 > "$work/sleep-$ending-0001-alpha"
  as_terminal "$ending" "$ending.log" "$repo/tests/run.sh"
  check "AC-06, $ending: the run holds the lock" started "$ending"
  case "$ending" in
    kill-9) kill -9 "$holder" ;;
    interrupted) kill -INT -- "-$holder" ;;
  esac
  wait "$holder" 2> /dev/null
  SECONDS=0
  RUN_ID="after-$ending" bash "$other/tests/run.sh" > "$work/after-$ending.log" 2>&1
  took=$SECONDS
  check "AC-06, $ending: the next run doesn't wait for it" starts_within "after-$ending.log" 10
done

touch "$work/fail-0001-alpha"
suite fails.log
rm "$work/fail-0001-alpha"
SECONDS=0
RUN_ID=after-failed bash "$other/tests/run.sh" > "$work/after-failed.log" 2>&1
took=$SECONDS
check "AC-06, a failed run: it failed" test "$status" -eq 1
check "AC-06, a failed run: the next run doesn't wait for it" starts_within after-failed.log 10
check "AC-06, a failed run: nor says it waits" test -z "$(grep '^waiting' "$work/after-failed.log")"
finish
