# tests/lib/suite-lock.sh as 8f0a090 has it, with no queue: the skills' copy's behaviour until their
# intent 0119, for tests/0037-queue.sh's AC-05 (a run without a queue beside queued ones).
#
# The suite's lock (0017, RQ-06): one run of tests/run.sh at a time per Docker. suite_lock_take waits,
# naming the holder's worktree and start time, until this run holds SUITE_LOCK_NAME: a container fed
# by a pipe from the run, gone when the run ends however it ends (tests/0017-run.sh); it returns 1 when
# docker fails otherwise. A command that may outlive the run gets `{SUITE_LOCK_FD}>&-`.
SUITE_LOCK_NAME=${SUITE_LOCK_NAME:-c4-infra.suite-lock}
SUITE_LOCK_FD=

suite_lock_take() {
  local started holder said='' answer
  started=$(date '+%Y-%m-%d %H:%M:%S')
  answer=$(mktemp)
  while :; do
    : > "$answer"
    exec {SUITE_LOCK_FD}> >(MSYS_NO_PATHCONV=1 docker run --rm -i --name "$SUITE_LOCK_NAME" \
      --label "c4-infra.suite.worktree=$PWD" --label "c4-infra.suite.started=$started" \
      alpine:3 sh -c 'echo held; exec cat > /dev/null' > "$answer" 2> "$answer.err")
    local docker_pid=$!
    while [ ! -s "$answer" ] && kill -0 "$docker_pid" 2> /dev/null; do
      sleep 0.2
    done
    if grep -qx held "$answer"; then
      rm -f "$answer" "$answer.err"
      return 0
    fi
    exec {SUITE_LOCK_FD}>&-
    if ! grep -q 'is already in use' "$answer.err"; then
      echo "the suite's lock ($SUITE_LOCK_NAME) can't be taken:" >&2
      cat "$answer.err" >&2
      rm -f "$answer" "$answer.err"
      return 1
    fi
    holder=$(docker container inspect -f \
      '{{index .Config.Labels "c4-infra.suite.worktree"}}, started {{index .Config.Labels "c4-infra.suite.started"}}' \
      "$SUITE_LOCK_NAME" 2> /dev/null)
    if [ -n "$holder" ] && [ "$holder" != "$said" ]; then
      echo "waiting for the run of $holder"
      said=$holder
    fi
    sleep 2
  done
}
