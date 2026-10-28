#!/usr/bin/env bash
# 0022: tests/run.sh's lanes (AC-02 to AC-06), on a throwaway git repository: a copy of tests/run.sh
# and tests/lib/, the scripts a.sh and b.sh, two fake tests that print three lines between pauses
# (0001-one, 0002-two) and three fake stand-in tests (0003-three, 0004-four, 0005-five) that do the
# same, saying the stand-in name and volume they were given, with a container of that name
# (alpine) as their stand-in host, removed when they end. The runs take a lock and stand-in names of
# their own (SUITE_LOCK_NAME, STAND_IN_NAME, STAND_IN_VOLUME), and see 20 GB of Docker memory
# (SUITE_DOCKER_MEMORY) unless a check says otherwise.
#
#   bash tests/0022-lanes.sh
#
# Measured at 0022's step 1 (Linux, Docker Desktop given 12 GiB): two stand-in tests at once, each on
# its own stand-in host, beside the dev stack, both pass (0003-demo-deploy 123 s, 0012-themes 298 s,
# its new volume pulling its images); the sum of docker stats peaks at 6000 MiB, 50 % of 11955 MiB.
# Not measured under Git Bash (set -m, a process group's TERM, Ctrl-C in a Windows console).
#
# covers: tests/run.sh tests/lib/suite-lock.sh
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

work=$(mktemp -d)
repo=$work/repo
other=$work/other
export SUITE_LOCK_NAME=c4-infra.suite-lock-0022-$$
export STAND_IN_NAME=c4-infra-stand-in-0022-$$
export STAND_IN_VOLUME=c4-infra-stand-in-0022-$$-docker
export SUITE_DOCKER_MEMORY=20000000000
HOSTS=("$STAND_IN_NAME" "$STAND_IN_NAME-2")

cleanup() { # the fake tests and their sleeps, the stand-in containers
  local pid
  for pid in $(cat "$work"/pid-* "$work"/sleeps-* 2> /dev/null); do
    kill "$pid" 2> /dev/null
  done
  docker rm -f "${HOSTS[@]}" "$SUITE_LOCK_NAME" > /dev/null 2>&1
  rm -rf "$work"
}
trap cleanup EXIT

git_() {
  git -C "$repo" -c user.name=0022 -c user.email=0022@verif.test "$@"
}

# <name> <covers…>: prints "<name> 1" to "<name> 3", 0.3 s apart ($work/sleep-<name> changes the
# pause), logs its start and end with the run's RUN_ID, its pid in $work/pid-<run> and its sleeps'
# in $work/sleeps-<run> (in the foreground, as a real test's commands); a stand-in one keeps a
# container named $STAND_IN_NAME meanwhile; $work/fail-<name> fails it, $work/kill-lane-<name> kills
# its lane (its parent) first
fake_test() {
  local name=$1
  shift
  cat > "$repo/tests/$name.sh" << EOF
#!/usr/bin/env bash
# a fake test of tests/0022-lanes.sh
# covers: $*
echo \$\$ >> "$work/pid-\${RUN_ID:-run}"
echo "\${RUN_ID:-run} $name start \$EPOCHREALTIME" >> "$work/order.log"
if [[ $name == *.stand-in ]]; then
  trap 'docker rm -f "\$STAND_IN_NAME" > /dev/null 2>&1' EXIT
  docker run -d --name "\$STAND_IN_NAME" alpine:3 sleep 600 > /dev/null
  echo "$name stand-in \$STAND_IN_NAME \$STAND_IN_VOLUME"
fi
[ ! -e "$work/kill-lane-$name" ] || kill -9 \$PPID
for line in 1 2 3; do
  echo "$name \$line"
  sh -c 'echo \$\$ >> "\$1"; exec sleep "\$2"' sh "$work/sleeps-\${RUN_ID:-run}" \
    "\$(cat "$work/sleep-$name" 2> /dev/null || echo 0.3)"
done
echo "\${RUN_ID:-run} $name end \$EPOCHREALTIME" >> "$work/order.log"
[ ! -e "$work/fail-$name" ]
EOF
}

mkdir -p "$repo/tests/lib"
cp tests/run.sh "$repo/tests/"
cp tests/lib/*.sh "$repo/tests/lib/"
fake_test 0001-one a.sh
fake_test 0002-two b.sh
fake_test 0003-three.stand-in a.sh
fake_test 0004-four.stand-in a.sh
fake_test 0005-five.stand-in a.sh
echo true > "$repo/a.sh"
echo true > "$repo/b.sh"
git_ init -q -b main
git_ add -A
git_ commit -q -m base
git_ worktree add -q --detach "$other" main
durations=$(git -C "$repo" rev-parse --absolute-git-dir)/c4-infra-test-durations

suite() { # <log> <option…>: tests/run.sh in the repository, its status in $status
  local log=$1
  shift
  bash "$repo/tests/run.sh" "$@" > "$work/$log" 2>&1
  status=$?
}

ran() { # <log>: the tests it printed, in order, by name
  sed -n 's|^== tests/\([^ :]*\)\.sh$|\1|p' "$work/$1" | tr '\n' ' ' | sed 's/ $//'
}

ran_set() { # <log> <names, sorted>
  [ "$(ran "$1" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')" = "$2" ] || { cat "$work/$1"; return 1; }
}

passed() { # <log>
  [ "$status" -eq 0 ] || { echo "exit $status"; cat "$work/$1"; return 1; }
}

no_start_line() { # <log>
  ! grep -n ' started (lane ' "$work/$1"
}

# every line between a test's "== tests/<name>.sh" and its "-- tests/<name>.sh: <n.n> s" is its own
whole_blocks() { # <log>
  awk '
    /^== tests\/[^ :]*\.sh$/ { name = $2; sub(/^tests\//, "", name); sub(/\.sh$/, "", name); inside = 1; next }
    inside && /^-- tests\// {
      if (index($0, "-- tests/" name ".sh: ") != 1 || $0 !~ / [0-9]+\.[0-9] s$/) { print name "'"'"'s block closed by: " $0; bad = 1 }
      inside = 0; next
    }
    inside && index($0, name " ") != 1 { print "in " name "'"'"'s block: " $0; bad = 1 }
    END { exit bad }
  ' "$work/$1" || { cat "$work/$1"; return 1; }
}

started_in() { # <log> <name> <lane text>
  grep -qE "^== tests/$2\.sh started \($3[,)].*its output in " "$work/$1" || { cat "$work/$1"; return 1; }
}

stand_in_of() { # <log> <name>: the stand-in name and volume it was given
  sed -n "s|^$2 stand-in ||p" "$work/$1"
}

no_host_left() {
  local left
  left=$(docker ps -aq --filter "name=^$STAND_IN_NAME") || return 1
  [ -z "$left" ] || { docker ps -a --filter "name=^$STAND_IN_NAME" --format '{{.Names}} {{.Status}}'; return 1; }
}

# AC-04: no stand-in test, no lane
suite plain.log
check "AC-04: plain: passes" passed plain.log
check "AC-04: plain: the tests in the suite's order" test "$(ran plain.log)" = "0001-one 0002-two"
check "AC-04: plain: no start line" no_start_line plain.log
echo '# changed' >> "$repo/b.sh"
suite changed.log --changed
check "AC-04: --changed without a stand-in test: no start line" no_start_line changed.log
check "AC-04: --changed without a stand-in test: the one test" test "$(ran changed.log)" = "0002-two"
git_ checkout -q b.sh

# AC-02, AC-06: --all in three lanes, no duration recorded yet
rm -f "$durations"
suite all.log --all
check "AC-02: --all: passes" passed all.log
check "AC-02: --all: every test once" ran_set all.log "0001-one 0002-two 0003-three.stand-in 0004-four.stand-in 0005-five.stand-in"
check "AC-02: each test's output whole, between its own lines" whole_blocks all.log
check "AC-02: the others' start line" started_in all.log 0001-one "lane 1"
check "AC-02: a stand-in test's start line" started_in all.log 0003-three.stand-in "lane [23], stand-in $STAND_IN_NAME(-2)?"
check "AC-02: the total, then the slowest" grep -qE '^total: [0-9]+\.[0-9] s for 5 test\(s\); the slowest:$' "$work/all.log"
check "AC-02: its last line" test "$(tail -n 1 "$work/all.log")" = "verification passed"
check "AC-06: two stand-in tests got two different hosts" \
  test "$(stand_in_of all.log 0003-three.stand-in)" != "$(stand_in_of all.log 0004-four.stand-in)"
check "AC-06: the first host is $STAND_IN_NAME, its volume $STAND_IN_VOLUME" \
  test "$(stand_in_of all.log 0003-three.stand-in)" = "$STAND_IN_NAME $STAND_IN_VOLUME"
check "AC-06: the second, $STAND_IN_NAME-2 and its own volume" \
  test "$(stand_in_of all.log 0004-four.stand-in)" = "$STAND_IN_NAME-2 c4-infra-stand-in-0022-$$-2-docker"
check "AC-06: never run before, the third goes back to the first host" \
  test "$(stand_in_of all.log 0005-five.stand-in)" = "$STAND_IN_NAME $STAND_IN_VOLUME"
check "AC-06: no stand-in host left after a run that passed" no_host_left
check "the durations are recorded for the next split" grep -q '^tests/0004-four.stand-in.sh [0-9][0-9]*$' "$durations"

# PA-01: the longest first, each to the least loaded host
printf '%s\n' "tests/0003-three.stand-in.sh 30000000" "tests/0004-four.stand-in.sh 20000000" \
  "tests/0005-five.stand-in.sh 10000000" > "$durations"
suite split.log --all
check "PA-01: the longest (three) on a host of its own" \
  test "$(stand_in_of split.log 0004-four.stand-in)" = "$(stand_in_of split.log 0005-five.stand-in)"
check "PA-01: the two others together on the other one" \
  test "$(stand_in_of split.log 0003-three.stand-in)" != "$(stand_in_of split.log 0004-four.stand-in)"

# PA-03: under 9 GiB, one stand-in lane, said
SUITE_DOCKER_MEMORY=6206390272 suite small.log --all
SUITE_DOCKER_MEMORY=6G suite not-a-number.log --all
check "PA-03: a memory that isn't a number counts as none" grep -qF '== Docker reports 0.0 GiB' "$work/not-a-number.log"
check "PA-03: 6 GiB: the run says so" grep -qF '== Docker reports 5.8 GiB, under the 9 GiB of Docker Desktop given 10 GiB, which two stand-in lanes need (CLAUDE.md): one stand-in lane' "$work/small.log"
check "PA-03: 6 GiB: one host for the three stand-in tests" \
  test "$(stand_in_of small.log 0003-three.stand-in)|$(stand_in_of small.log 0005-five.stand-in)" \
  = "$STAND_IN_NAME $STAND_IN_VOLUME|$STAND_IN_NAME $STAND_IN_VOLUME"
check "PA-03: 6 GiB: still passes" grep -qx 'verification passed' "$work/small.log"

# PA-01: a test never run before beside one that was: each still on a host of its own
printf '%s\n' "tests/0003-three.stand-in.sh 30000000" > "$durations"
suite new-test.log --all
check "PA-01: a new test and a known one: the run passes" passed new-test.log
check "PA-01: a new test and a known one: on two hosts" \
  test "$(stand_in_of new-test.log 0003-three.stand-in)" != "$(stand_in_of new-test.log 0004-four.stand-in)"

# AC-03: a failed stand-in test, the other lanes go on; its duration isn't recorded
four_before=$(grep '^tests/0004-four.stand-in.sh ' "$durations")
touch "$work/fail-0004-four.stand-in"
RUN_ID=failed suite failed.log --all
rm "$work/fail-0004-four.stand-in"
ended() { # <run> <names>: each one ran to its end
  local name
  for name in $2; do
    grep -q "^$1 $name end " "$work/order.log" || { echo "$name didn't end"; return 1; }
  done
}
check "a failed test's duration isn't recorded" grep -qxF "$four_before" "$durations"
check "AC-03: exit 1" test "$status" -eq 1
check "AC-03: FAILED lists it alone" test "$(sed -n '/^FAILED:$/,$p' "$work/failed.log")" = "$(printf 'FAILED:\n  tests/0004-four.stand-in.sh')"
check "AC-03: every other test ran to its end, in the other lanes as in its own" \
  ended failed "0001-one 0002-two 0003-three.stand-in 0005-five.stand-in"
check "AC-03: no test left without a result" test -z "$(grep -- ': no result, ' "$work/failed.log")"
check "AC-06: no stand-in host left after a run that failed" no_host_left

# a lane gone before its tests end (killed): the run doesn't wait for them, they fail
touch "$work/kill-lane-0001-one"
SECONDS=0
timeout 120 bash "$repo/tests/run.sh" --all > "$work/lane-gone.log" 2>&1
status=$?
took=$SECONDS
rm "$work/kill-lane-0001-one"
check "a lane gone: the run ends (exit 1, in $took s)" test "$status" -eq 1
check "a lane gone: its tests are listed under FAILED" grep -qxF '  tests/0002-two.sh' "$work/lane-gone.log"
check "a lane gone: saying why" grep -qF -- '-- tests/0002-two.sh: no result, its lane ended before it' "$work/lane-gone.log"

# AC-05: a run with lanes holds the lock until its last lane ends, kill -9 included; a run
# interrupted leaves no test running. A run is started as a terminal starts it (SIGINT at its
# default, a process group of its own), so that Ctrl-C can be sent to it
started() { # <run> <name>
  local i
  for ((i = 0; i < 100; i++)); do
    grep -q "^$1 $2 start" "$work/order.log" 2> /dev/null && return 0
    sleep 0.2
  done
  echo "$1's $2 never started"
  return 1
}
as_terminal() { # <run> <log> <option…>: in the background, its pid in $holder
  local run=$1 log=$2
  shift 2
  RUN_ID=$run perl -e '$SIG{INT} = "DEFAULT"; setpgrp(0, 0); exec @ARGV' bash "$repo/tests/run.sh" "$@" \
    > "$work/$log" 2>&1 &
  holder=$!
}
first_start_after_last_end() { # <second run> <first run>
  awk -v b="$1" -v a="$2" '
    $1 == a && $3 == "end" && $4 > last { last = $4 }
    $1 == b && $3 == "start" && (first == "" || $4 < first) { first = $4 }
    END { if (first == "" || first <= last) { print "first start of " b ": " first ", last end of " a ": " last; exit 1 } }
  ' "$work/order.log"
}
none_running() { # <run>: none of its fake tests' processes live, nor their commands
  local pid left=""
  for pid in $(cat "$work/pid-$1" "$work/sleeps-$1" 2> /dev/null); do
    kill -0 "$pid" 2> /dev/null && left="$left $pid"
  done
  [ -z "$left" ] || { echo "still running:$left"; ps -o pid,args -p ${left// /,} 2> /dev/null; return 1; }
}

echo 1 > "$work/sleep-0004-four.stand-in"
for ending in waits kill-9; do
  as_terminal "$ending" "$ending.log" --all
  check "AC-05, $ending: its stand-in lane has started" started "$ending" 0004-four.stand-in
  [ "$ending" = kill-9 ] && kill -9 "$holder"
  RUN_ID="after-$ending" bash "$other/tests/run.sh" > "$work/after-$ending.log" 2>&1
  wait "$holder" 2> /dev/null
  check "AC-05, $ending: the next run waits" grep -q '^waiting for the run of ' "$work/after-$ending.log"
  check "AC-05, $ending: and starts after its last lane's end" first_start_after_last_end "after-$ending" "$ending"
done
check "AC-05, kill-9: no lane starts another test" test -z "$(grep '^kill-9 0002-two start' "$work/order.log")"

echo 30 > "$work/sleep-0004-four.stand-in"
as_terminal interrupted interrupted.log --all
check "AC-05, interrupted: its stand-in lane has started" started interrupted 0004-four.stand-in
sleep 1
kill -INT -- "-$holder"
SECONDS=0
wait "$holder" 2> /dev/null
check "AC-05, interrupted: the run ends at once (in less than 10 s)" test "$SECONDS" -lt 10
check "AC-05, interrupted: it says so" grep -qF 'interrupted: every lane stopped' "$work/interrupted.log"
sleep 2
check "AC-05, interrupted: no test of any lane goes on" none_running interrupted
check "AC-06: no stand-in host left after a run interrupted" no_host_left

# a hangup (the terminal or ssh session closed: SIGHUP to the run's process group) as Ctrl-C
as_terminal hangup hangup.log --all
check "AC-05, a hangup: its stand-in lane has started" started hangup 0004-four.stand-in
sleep 1
kill -HUP -- "-$holder"
wait "$holder" 2> /dev/null
sleep 2
check "AC-05, a hangup: no test of any lane goes on" none_running hangup
check "AC-06: no stand-in host left after a hangup" no_host_left
finish
