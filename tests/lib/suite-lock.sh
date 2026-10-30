# The suite's lock (0017, RQ-06) and its queue (0037): one run of tests/run.sh at a time per Docker,
# the runs waiting for it taking it in the order they arrived. suite_lock_take returns once this run
# holds SUITE_LOCK_NAME: a container fed by a pipe from the run, gone when the run ends however it ends
# (tests/0017-run.sh); it returns 1 when docker fails otherwise. A command that may outlive the run
# gets `{SUITE_LOCK_FD}>&-`.
#
# The queue's protocol, for every copy of this library (the skills' tests share the lock):
#   - a run first starts its ticket, an alpine:3 container fed by a pipe from the run as the lock is,
#     so gone within a second or two when the run ends however it ends: named
#     <SUITE_LOCK_NAME>.queue.<pid>-<random>, labelled c4-infra.suite.queue=<SUITE_LOCK_NAME> and, as
#     the lock is, c4-infra.suite.worktree and c4-infra.suite.started;
#   - the queue is the running containers labelled c4-infra.suite.queue=<SUITE_LOCK_NAME>, ordered by
#     their .State.StartedAt (the Docker daemon's clock, one for all its clients; its fraction padded
#     to 9 digits), then their .Id; a run's place is its ticket's rank;
#   - every second, the run at place 1 tries the lock, the others don't; once it holds the lock, it
#     closes its ticket's pipe;
#   - a waiting run prints "waiting for the run of <worktree>, started <time>" when the holder
#     changes, and "place in the queue: <n>" when its place changes (1: it is next);
#   - a run whose ticket is gone takes another one, at the end of the queue.
# A copy without the queue still never holds the lock beside a run that queues, but can take it ahead
# of the queue. `docker rm -f <ticket>` sends a run to the end of the queue; `docker rm -f
# c4-infra.suite-lock` frees the lock of a run that hangs.
SUITE_LOCK_NAME=${SUITE_LOCK_NAME:-c4-infra.suite-lock}
SUITE_LOCK_FD=
_suite_lock_pipe=

_suite_lock_open() { # <name> <word> <fd its process doesn't keep, or ''> <label>…: a container fed by a pipe from this shell, the pipe's fd in _suite_lock_pipe; 0 once it says the word, 2 when the name is in use, 1 when docker fails otherwise
  local name=$1 word=$2 other=$3 answer docker_pid label labels=()
  shift 3
  for label in "$@"; do
    labels+=(--label "$label")
  done
  answer=$(mktemp)
  exec {_suite_lock_pipe}> >(if [ -n "$other" ]; then exec {other}>&-; fi
    MSYS_NO_PATHCONV=1 exec docker run --rm -i --name "$name" "${labels[@]}" \
      alpine:3 sh -c "echo $word; exec cat > /dev/null" > "$answer" 2> "$answer.err")
  docker_pid=$!
  while [ ! -s "$answer" ] && kill -0 "$docker_pid" 2> /dev/null; do
    sleep 0.2
  done
  if grep -qx "$word" "$answer"; then
    rm -f "$answer" "$answer.err"
    return 0
  fi
  exec {_suite_lock_pipe}>&-
  if grep -q 'is already in use' "$answer.err"; then
    rm -f "$answer" "$answer.err"
    return 2
  fi
  echo "the suite's lock ($SUITE_LOCK_NAME) can't be taken:" >&2
  cat "$answer.err" >&2
  rm -f "$answer" "$answer.err"
  return 1
}

_suite_lock_queue() { # the queue's tickets, the first in line first: one id per line
  docker ps -q --no-trunc --filter "label=c4-infra.suite.queue=$SUITE_LOCK_NAME" \
    | xargs -r docker container inspect -f '{{.State.StartedAt}} {{.Id}}' 2> /dev/null | tr -d '\r' \
    | awk '{ time = $1; sub(/Z$/, "", time); fraction = ""; dot = index(time, ".")
        if (dot) { fraction = substr(time, dot + 1); time = substr(time, 1, dot - 1) }
        print time "." substr(fraction "000000000", 1, 9) " " $2 }' \
    | LC_ALL=C sort | cut -d' ' -f2
}

suite_lock_take() {
  local started ticket ticket_fd id='' place told='' holder said=''
  started=$(date '+%Y-%m-%d %H:%M:%S')
  while :; do
    if [ -z "$id" ]; then
      ticket=$SUITE_LOCK_NAME.queue.$$-$RANDOM$RANDOM
      _suite_lock_open "$ticket" queued '' "c4-infra.suite.queue=$SUITE_LOCK_NAME" \
        "c4-infra.suite.worktree=$PWD" "c4-infra.suite.started=$started"
      case $? in
        0) ticket_fd=$_suite_lock_pipe ;;
        2) continue ;;
        *) return 1 ;;
      esac
      id=$(docker container inspect -f '{{.Id}}' "$ticket" 2> /dev/null | tr -d '\r')
    fi
    place=$(_suite_lock_queue | grep -nxF -- "$id" | cut -d: -f1)
    if [ -z "$place" ]; then
      exec {ticket_fd}>&-
      id=''
      continue
    fi
    if [ "$place" = 1 ]; then
      _suite_lock_open "$SUITE_LOCK_NAME" held "$ticket_fd" \
        "c4-infra.suite.worktree=$PWD" "c4-infra.suite.started=$started"
      case $? in
        0)
          SUITE_LOCK_FD=$_suite_lock_pipe
          exec {ticket_fd}>&-
          return 0
          ;;
        1)
          exec {ticket_fd}>&-
          return 1
          ;;
      esac
    fi
    holder=$(docker container inspect -f \
      '{{index .Config.Labels "c4-infra.suite.worktree"}}, started {{index .Config.Labels "c4-infra.suite.started"}}' \
      "$SUITE_LOCK_NAME" 2> /dev/null | tr -d '\r')
    if [ -n "$holder" ] && [ "$holder" != "$said" ]; then
      echo "waiting for the run of $holder"
      said=$holder
    fi
    if [ "$place" != "$told" ]; then
      echo "place in the queue: $place"
      told=$place
    fi
    sleep 1 {ticket_fd}>&-
  done
}
