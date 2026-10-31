#!/usr/bin/env bash
# 0049: tests/run.sh's Docker preflight, on the host's Docker, with a lock and a label namespace of its
# own (C4_DOCKER_LABEL_NS=c4-test-0049-<pid>, C4_DOCKER_REAP=labelled: nothing it didn't create is
# touched), on a throwaway git repository: a copy of tests/run.sh, tests/lib/ and tests/docker-pins.sh,
# a fake test that creates a container, a volume and a network with the labels and holds them while
# $work/hold-<run> exists, and a fake stand-in test that only sleeps:
#
#   - the label contract: docker_labels prints <ns>.owner, .run, .created, .ttl (and .lock with
#     C4_DOCKER_LOCK), the run the same in a command substitution; docker_keep_labels its two;
#   - AC-03: a run killed with kill -9, its test killed too, while that test holds what it created: the
#     next run that takes the lock removes them before its first test, and says how many; and that run
#     leaves nothing of its own id;
#   - AC-05: a floor above what is free: the run exits 1 before its first test, the shortage named;
#     with C4_DOCKER_PREFLIGHT=off, the same run starts and passes;
#   - AC-07: a run whose lanes run tests (--all, the fake stand-in test): no prune nor removal reaches
#     Docker (a docker shim's log) between its first test's start and its last test's end;
#   - AC-09: the host's memory and disk named as measured: under Git Bash (Docker Desktop on WSL2),
#     MemFree and SwapFree, and the drive C:; on Linux, MemAvailable.
#
#   bash tests/0049-docker-preflight.sh
#
# covers: tests/run.sh tests/lib/docker-preflight.sh tests/lib/suite-lock.sh tests/docker-pins.sh
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

work=$(mktemp -d)
repo=$work/repo
NS=c4-test-0049-$$
# what a run of the real suite exports must not reach the throwaway runs
unset C4_INFRA_RUN C4_DOCKER_LOCK C4_DOCKER_PREFLIGHT C4_DOCKER_MIN_VM_DISK_GB C4_DOCKER_MIN_HOST_DISK_GB \
  C4_DOCKER_MIN_VM_MEMORY_GIB C4_DOCKER_MIN_HOST_MEMORY_GIB C4_DOCKER_BUILD_CACHE_GB C4_DOCKER_DISK_DIR
export SUITE_LOCK_NAME=c4-infra.suite-lock-0049-$$ C4_DOCKER_LABEL_NS=$NS C4_DOCKER_REAP=labelled
export STAND_IN_NAME=c4-infra-stand-in-0049-$$ STAND_IN_VOLUME=c4-infra-stand-in-0049-$$-docker
export SUITE_DOCKER_MEMORY=1 WORK=$work NS
REAL_DOCKER=$(command -v docker)

mine() { # <ps|volume ls|network ls> …: what this test created, by its label or its names' prefix
  { docker "$@" -q --filter "label=$NS.run"; docker "$@" -q --filter "name=$NS-"; } 2> /dev/null | tr -d '\r' | LC_ALL=C sort -u
}
cleanup() {
  local pid id
  for pid in $(cat "$work"/pid-* 2> /dev/null); do
    kill -9 "$pid" 2> /dev/null
  done
  for id in $(mine ps -a); do docker rm -f -v "$id" > /dev/null 2>&1; done
  for id in $(mine network ls); do docker network rm "$id" > /dev/null 2>&1; done
  for id in $(mine volume ls); do docker volume rm "$id" > /dev/null 2>&1; done
  docker ps -aq --filter "label=c4-infra.suite.queue=$SUITE_LOCK_NAME" | tr -d '\r' | xargs -r docker rm -f -v > /dev/null 2>&1
  docker rm -f -v "$SUITE_LOCK_NAME" > /dev/null 2>&1
  rm -rf "$work"
}
trap cleanup EXIT

mkdir -p "$repo/tests/lib" "$work/shim"
cp tests/run.sh tests/docker-pins.sh "$repo/tests/" 2> /dev/null
cp tests/lib/*.sh "$repo/tests/lib/"
cat > "$repo/tests/0001-holder.sh" << 'EOF'
#!/usr/bin/env bash
# a fake test of tests/0049-docker-preflight.sh: a container, a volume and a network, labelled, held
# while $WORK/hold-$RUN_ID exists (60 s at most), then removed; nothing with Docker in run E
echo $$ > "$WORK/pid-$RUN_ID-holder"
echo "$RUN_ID start $(date +%s%N)" >> "$WORK/order.log"
if [ "$RUN_ID" = E ]; then
  sleep 1
  echo "$RUN_ID end $(date +%s%N)" >> "$WORK/order.log"
  exit 0
fi
source tests/lib/docker-preflight.sh
mapfile -t C4_LABELS < <(docker_labels c4-test)
docker run -d "${C4_LABELS[@]}" --name "$NS-$RUN_ID-c" alpine:3 sleep 300 > /dev/null
docker volume create "${C4_LABELS[@]}" "$NS-$RUN_ID-v" > /dev/null
docker network create "${C4_LABELS[@]}" "$NS-$RUN_ID-n" > /dev/null
: > "$WORK/created-$RUN_ID"
while [ -e "$WORK/hold-$RUN_ID" ] && [ "$SECONDS" -lt 60 ]; do
  sleep 0.2
done
echo "$RUN_ID end $(date +%s%N)" >> "$WORK/order.log"
docker rm -f -v "$NS-$RUN_ID-c" > /dev/null
docker network rm "$NS-$RUN_ID-n" > /dev/null
docker volume rm "$NS-$RUN_ID-v" > /dev/null
EOF
cat > "$repo/tests/0002-lane.stand-in.sh" << 'EOF'
#!/usr/bin/env bash
# a fake stand-in test of tests/0049-docker-preflight.sh: it only sleeps
echo "$RUN_ID start $(date +%s%N)" >> "$WORK/order.log"
sleep 1
echo "$RUN_ID end $(date +%s%N)" >> "$WORK/order.log"
EOF
cat > "$work/shim/docker" << EOF
#!/usr/bin/env bash
echo "\$(date +%s%N) \$*" >> "$work/docker.log"
exec "$REAL_DOCKER" "\$@"
EOF
git -C "$repo" init -q -b main
git -C "$repo" -c user.name=0049 -c user.email=0049@verif.test add -A
git -C "$repo" -c user.name=0049 -c user.email=0049@verif.test commit -q -m base

suite() { # <run> <option…>: tests/run.sh of the repository, its output in $work/<run>.log, its status in $status
  local run=$1
  shift
  RUN_ID=$run timeout 300 bash "$repo/tests/run.sh" "$@" > "$work/$run.log" 2>&1
  status=$?
}
says() { # <run> <pattern>
  grep -qE "$2" "$work/$1.log" || { cat "$work/$1.log"; return 1; }
}
# a test's start, in turn (`== <test>`) or in a lane (`== <test> started …`); not a skipped one's line
TEST_START='^== tests/[^ :]*\.sh( started .*)?$'
no_test_started() { # <run>
  ! grep -qE "$TEST_START" "$work/$1.log" && ! grep -q "^$1 start" "$work/order.log" 2> /dev/null \
    || { cat "$work/$1.log"; return 1; }
}
before_first_test() { # <run> <pattern>: a line of the run, before its first test's start
  local at first
  at=$(grep -nE "$2" "$work/$1.log" | head -n 1 | cut -d: -f1)
  first=$(grep -nE "$TEST_START" "$work/$1.log" | head -n 1 | cut -d: -f1)
  [ -n "$at" ] && { [ -z "$first" ] || [ "$at" -lt "$first" ]; } || { cat "$work/$1.log"; return 1; }
}
gone() { # <ps -a|volume ls|network ls> <name>
  [ -z "$(docker $1 -q --filter "name=$2" 2> /dev/null | tr -d '\r')" ]
}

# the label contract
contract=$(C4_DOCKER_LOCK=the-lock bash -c 'source tests/lib/docker-preflight.sh
  echo "run $C4_INFRA_RUN"
  docker_labels some-owner 60
  echo "inner $(bash -c "echo \$C4_INFRA_RUN")"
  docker_keep_labels some-owner /some/path' 2>&1 | tr -d '\r')
run=$(sed -n 's/^run //p' <<< "$contract")
created=$(sed -n "s/^$NS\.created=//p" <<< "$contract")
labels_printed() {
  local got expected
  got=$(sed -n '/^run /,/^inner /p' <<< "$contract" | sed '1d;$d')
  expected=$(printf -- '--label\n%s\n' "$NS.owner=some-owner" "$NS.run=$run" "$NS.created=$created" "$NS.ttl=60" "$NS.lock=the-lock")
  [[ $created =~ ^[0-9]+$ ]] && [ "$got" = "$expected" ] || { echo "got:"; printf '%s\n' "$got"; return 1; }
}
check "docker_labels prints the label contract's arguments" labels_printed
check "the run is set, and the same in a child process" eval '[ -n "$run" ] && grep -qxF "inner $run" <<< "$contract"'
check "docker_keep_labels prints its two labels" grep -qxF "$NS.keep=/some/path" <<< "$contract"

# AC-03: a run killed with kill -9 while its test holds its resources, then the next run
: > "$work/hold-A"
RUN_ID=A bash "$repo/tests/run.sh" > "$work/A.log" 2>&1 &
echo $! > "$work/pid-A-run"
for ((i = 0; i < 300; i++)); do
  [ -e "$work/created-A" ] && break
  sleep 0.2
done
check "AC-03: the first run's test created its container, volume and network" test -e "$work/created-A"
kill -9 "$(cat "$work/pid-A-run")" "$(cat "$work/pid-A-holder" 2> /dev/null)" 2> /dev/null
rm -f "$work/hold-A"
sleep 2
check "AC-03: killed, its container stays" eval '! gone "ps -a" "$NS-A-c"'
suite B
check "AC-03: the next run passes" test "$status" -eq 0
check "AC-03: it removed them before its first test, and says how many" \
  before_first_test B "^docker preflight: runs over: 1 container\(s\), 1 network\(s\), 1 volume\(s\), 0 image\(s\) removed$"
check "AC-03: the container is gone" gone "ps -a" "$NS-A-c"
check "AC-03: the volume is gone" gone "volume ls" "$NS-A-v"
check "AC-03: the network is gone" gone "network ls" "$NS-A-n"
run_b=$(sed -n 's/^docker preflight: run //p' "$work/B.log")
check "AC-03: the run names its id" test -n "$run_b"
check "AC-03: nothing of that run is left" \
  eval '[ -n "$run_b" ] && [ -z "$(for k in "ps -a" "volume ls" "network ls"; do docker $k -q --filter "label=$NS.run=$run_b"; done | tr -d "\r")" ]'

# AC-09: the host's memory and disk, as measured here
if command -v cygpath > /dev/null; then
  check "AC-09: the host's memory from MemFree and SwapFree (Git Bash)" \
    says B "^docker preflight: host memory: [0-9.]+ GiB MemFree \+ [0-9.]+ GiB SwapFree \(floor 6\)$"
  check "AC-09: the host's disk under Docker's disk image, on C:" \
    says B "^docker preflight: host disk under Docker's disk image \(C:\): [0-9.]+ GB free \(floor 20\)$"
else
  check "AC-09: the host's memory from MemAvailable (Linux)" says B "^docker preflight: host memory: [0-9.]+ GiB MemAvailable"
fi
check "AC-09: Docker's VM measured" says B "^docker preflight: VM memory: [0-9.]+ GiB available \(floor 3\)$"

# AC-05: a floor above what is free, then the preflight off
C4_DOCKER_MIN_VM_DISK_GB=1000000000 suite C
check "AC-05: a floor above what is free: exit 1" test "$status" -eq 1
check "AC-05: the shortage named" says C "^docker preflight: short: Docker's disk has [0-9.]+ GB free, 1000000000 needed"
check "AC-05: before any test" no_test_started C
C4_DOCKER_PREFLIGHT=off C4_DOCKER_MIN_VM_DISK_GB=1000000000 suite D
check "AC-05: with C4_DOCKER_PREFLIGHT=off, it starts and passes" \
  eval '[ "$status" -eq 0 ] && grep -q "^D start" "$work/order.log" && grep -qx "verification passed" "$work/D.log" || { cat "$work/D.log"; false; }'

# AC-07: a run with lanes, its docker calls logged
: > "$work/docker.log"
PATH="$work/shim:$PATH" suite E --all
check "AC-07: the run with lanes passes" test "$status" -eq 0
check "AC-07: the shim saw the preflight's reaping, before the tests" grep -q " ps -a --filter label=$NS.run " "$work/docker.log"
cleaning_during_tests() {
  awk -v from="$(awk '$1 == "E" && $2 == "start" { print $3 }' "$work/order.log" | LC_ALL=C sort -n | head -n 1)" \
    -v to="$(awk '$1 == "E" && $2 == "end" { print $3 }' "$work/order.log" | LC_ALL=C sort -n | tail -n 1)" '
    from == "" || to == "" { print "no test start or end logged"; bad = 1; exit }
    $1 >= from && $1 <= to && / (prune|rmi|rm|volume rm|network rm|image rm)( |$)/ { print; bad = 1 }
    END { exit bad }' "$work/docker.log"
}
check "AC-07: no prune nor removal between the first test's start and the last test's end" cleaning_during_tests
finish
