#!/usr/bin/env bash
# 0037: the suite's lock queues the runs that wait for it (tests/lib/suite-lock.sh), on locks of its
# own. Each run is a script in a directory of its own (its worktree) that sources a library, takes the
# lock, logs its start, holds the lock until the test releases it, then logs its end:
#
#   - AC-01, AC-02: A holds the lock; B, C and D start waiting in turn, each once the previous one
#     printed its place: each prints the line naming A, then its place; released one by one, they run
#     in arrival order, their places moving up;
#   - AC-03: K, waiting first, is killed with kill -9 (in a second round, interrupted as Ctrl-C
#     interrupts a terminal's process group): W, behind it, is first within 5 s, and runs once the
#     holder ends;
#   - AC-04: a run alone holds the lock within 10 s, printing nothing; a run on another lock holds
#     that one while this one is held; each queue counts its own runs only;
#   - AC-05: runs of the library and of tests/fixtures/0037/suite-lock-unqueued.sh (the library with
#     no queue, as the skills' copy has it) never hold the lock at the same time;
#   - AC-06: the library's header states the protocol; CLAUDE.md, the order and the place line.
#
#   bash tests/0037-queue.sh      (on a Linux Docker: tests/0037-queue-linux.stand-in.sh)
#
# covers: tests/lib/suite-lock.sh tests/fixtures/0037/ CLAUDE.md
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
# EPOCHREALTIME's decimal point, for the logs' times
export LC_ALL=C

LIB=$PWD/tests/lib/suite-lock.sh
UNQUEUED=$PWD/tests/fixtures/0037/suite-lock-unqueued.sh
LOCK=c4-infra.suite-lock-0037-$$
OTHER=$LOCK-other
work=$(mktemp -d)
pids=()

cleanup() { # every run left, then the locks' containers and their tickets
  local pid lock
  for pid in "${pids[@]}"; do
    kill -9 -- "-$pid" 2> /dev/null || kill -9 "$pid" 2> /dev/null
  done
  docker rm -f "$LOCK" "$OTHER" > /dev/null 2>&1
  for lock in "$LOCK" "$OTHER"; do
    docker ps -aq --filter "label=c4-infra.suite.queue=$lock" | xargs -r docker rm -f > /dev/null 2>&1
  done
  rm -rf "$work"
}
trap cleanup EXIT

cat > "$work/run.sh" << 'EOF'
# one run: <name> <library> <work> <lock> <seconds it holds the lock once released>
name=$1 work=$3
mkdir -p "$work/$name" && cd "$work/$name" || exit 1
SUITE_LOCK_NAME=$4
source "$2"
suite_lock_take || exit 1
echo "$name start $EPOCHREALTIME" >> "$work/order.log"
until [ -e "$work/release-$name" ]; do sleep 0.1; done
sleep "$5"
echo "$name end $EPOCHREALTIME" >> "$work/order.log"
EOF

start() { # <name> [library] [lock] [hold]: a run in the background, its pid in $pid
  bash "$work/run.sh" "$1" "${2:-$LIB}" "$work" "${3:-$LOCK}" "${4:-0}" > "$work/$1.log" 2>&1 &
  pid=$!
  pids+=("$pid")
}
start_as_terminal() { # <name>: a run as a terminal starts it (SIGINT at its default, a process group of its own), so that Ctrl-C reaches it
  perl -e '$SIG{INT} = "DEFAULT"; setpgrp(0, 0); exec @ARGV' bash "$work/run.sh" "$1" "$LIB" "$work" "$LOCK" 0 \
    > "$work/$1.log" 2>&1 &
  pid=$!
  pids+=("$pid")
}
release() { # <name>…
  local name
  for name in "$@"; do
    touch "$work/release-$name"
  done
}
within() { # <seconds> <command…>: the command succeeds before that many seconds pass
  local deadline
  deadline=$(awk -v now="$EPOCHREALTIME" -v s="$1" 'BEGIN { printf "%.3f", now + s }')
  shift
  until "$@" > /dev/null 2>&1; do
    if awk -v now="$EPOCHREALTIME" -v d="$deadline" 'BEGIN { exit !(now > d) }'; then
      "$@"
      return 1
    fi
    sleep 0.2
  done
}
lock_free() { [ -z "$(docker ps -aq --filter "name=^$LOCK\$")" ]; }
started() { grep -q "^$1 start " "$work/order.log" 2> /dev/null; }
ended() { grep -q "^$1 end " "$work/order.log" 2> /dev/null; }
waits() { grep -q '^waiting for the run of ' "$work/$1.log"; }
places() { # <name>: the places its run printed, in order
  sed -n 's/^place in the queue: //p' "$work/$1.log" | tr '\n' ' ' | sed 's/ $//'
}
places_are() { # <name> <places>
  [ "$(places "$1")" = "$2" ] || { echo "places: $(places "$1")"; cat "$work/$1.log"; return 1; }
}
opens_with() { # <name> <holder>: its run printed the line naming the holder's run, then its place
  local first second
  first=$(sed -n 1p "$work/$1.log") second=$(sed -n 2p "$work/$1.log")
  [[ $first == "waiting for the run of $work/$2, started "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]" "* ]] \
    && [[ $second == "place in the queue: "* ]] || { cat "$work/$1.log"; return 1; }
}
in_order() { # <run>…: each one started after the previous one's end
  local previous='' run
  for run in "$@"; do
    if [ -n "$previous" ]; then
      awk -v a="$previous" -v b="$run" '$1 == a && $2 == "end" { e = $3 } $1 == b && $2 == "start" { s = $3 }
        END { if (e == "" || s == "" || s + 0 <= e + 0) { print b " started at " s ", " a " ended at " e; exit 1 } }' \
        "$work/order.log" || return 1
    fi
    previous=$run
  done
}
apart() { # <run>…: each one ran, none while another held the lock
  local run order
  for run in "$@"; do
    ended "$run" || { echo "$run didn't end"; cat "$work/order.log"; return 1; }
  done
  order=$(awk '$2 == "start" { print $3, $1 }' "$work/order.log" | grep -E " ($(IFS='|'; echo "$*"))\$" \
    | LC_ALL=C sort -n | cut -d' ' -f2)
  in_order $order || { cat "$work/order.log"; return 1; }
}
went_first() { # <holder> <waiting> <killed>: the waiting run ran after the holder, the killed one never
  in_order "$1" "$2" && ! started "$3"
}

# AC-01, AC-02
start A
check "A holds the lock" within 20 started A
for run in B C D; do
  start "$run"
  check "AC-02: $run waits and prints its place" within 10 grep -q '^place in the queue: ' "$work/$run.log"
done
for run in B C D; do
  check "AC-02: $run names A's run, then its place" opens_with "$run" A
done
check "AC-02: B is 1st" places_are B 1
check "AC-02: C is 2nd" places_are C 2
check "AC-02: D is 3rd" places_are D 3
release A
check "AC-01: B runs once A ends" within 20 started B
check "AC-02: then C is 1st" within 10 places_are C "2 1"
check "AC-02: and D 2nd" within 10 places_are D "3 2"
release B
check "AC-01: C runs once B ends" within 20 started C
check "AC-02: then D is 1st" within 10 places_are D "3 2 1"
release C
check "AC-01: D runs once C ends" within 20 started D
release D
check "AC-01: B, C and D ran in arrival order, each after the previous one's end" within 10 in_order A B C D

# AC-03
for ending in kill-9 interrupted; do
  holder=H-$ending killed=K-$ending waiting=W-$ending
  start "$holder"
  check "AC-03, $ending: $holder holds the lock" within 20 started "$holder"
  if [ "$ending" = interrupted ]; then start_as_terminal "$killed"; else start "$killed"; fi
  killed_pid=$pid
  check "AC-03, $ending: $killed waits 1st" within 10 places_are "$killed" 1
  start "$waiting"
  check "AC-03, $ending: $waiting waits 2nd" within 10 places_are "$waiting" 2
  case $ending in
    kill-9) kill -9 "$killed_pid" ;;
    interrupted) kill -INT -- "-$killed_pid" ;;
  esac
  check "AC-03, $ending: $waiting is 1st within 5 s" within 5 places_are "$waiting" "2 1"
  release "$holder"
  check "AC-03, $ending: $waiting runs once $holder ends" within 20 started "$waiting"
  release "$waiting"
  check "AC-03, $ending: $waiting ran after $holder, $killed never" within 10 went_first "$holder" "$waiting" "$killed"
done

# AC-04
check "AC-04: the lock is free" within 10 lock_free
start S
check "AC-04: a run alone holds the lock within 10 s" within 10 started S
check "AC-04: printing nothing" test ! -s "$work/S.log"
release S
check "AC-04: it ends" within 10 ended S
start H
check "AC-04: H holds the lock" within 20 started H
start X "$LIB" "$OTHER"
check "AC-04: a run on another lock holds that one meanwhile" within 10 started X
check "AC-04: printing nothing" test ! -s "$work/X.log"
start Y
start Z "$LIB" "$OTHER"
check "AC-04: each queue counts its own runs: Y is 1st on H's lock" within 10 places_are Y 1
check "AC-04: Z is 1st on X's" within 10 places_are Z 1
release H X Y Z
check "AC-04: H and Y ran apart" within 20 apart H Y
check "AC-04: X and Z ran apart" within 20 apart X Z

# AC-05
start H5
check "AC-05: H5 holds the lock" within 20 started H5
start Q "$LIB" "$LOCK" 1
check "AC-05: a queued run waits" within 10 waits Q
start O "$UNQUEUED" "$LOCK" 1
check "AC-05: a run with no queue waits" within 10 waits O
release Q O H5
check "AC-05: both ran, never at the same time as another" within 30 apart H5 Q O

# AC-06
header=$(sed -n '/^#/!q;p' "$LIB")
for text in c4-infra.suite.queue StartedAt 'the run at place 1 tries the lock' 'place in the queue'; do
  check "AC-06: the library's header names $text" grep -qF -- "$text" <<< "$header"
done
check "AC-06: CLAUDE.md says waiting runs take the lock in the order they arrived" \
  grep -qF 'in the order they arrived' CLAUDE.md
check "AC-06: CLAUDE.md names the place line" grep -qF 'place in the queue' CLAUDE.md
finish
