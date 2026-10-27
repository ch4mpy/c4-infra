# The suite's lock (0017, RQ-06): one run of tests/run.sh at a time per Docker, whatever the clone or
# worktree it runs from. Source it, then:
#
#   suite_lock_take    waits until the lock is this run's, saying once per holder which run holds
#                      it (its worktree and start time); the lock is released when this run ends.
#                      Returns 1, with docker's message, when docker fails for another reason
#
# The lock is a container, SUITE_LOCK_NAME (default c4-infra.suite-lock), whose stdin is a pipe from
# the run: however the run ends (exit, failure, Ctrl-C, kill -9), the pipe closes, the container's
# cat ends and --rm removes it (measured in 0017's step 1); a second `docker run --name` of it fails
# while it lives. SUITE_LOCK_FD is the pipe's end: close it for every command that may outlive the
# run (`{SUITE_LOCK_FD}>&-`), or that command holds the lock after the run's end.
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
