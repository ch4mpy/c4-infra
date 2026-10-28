#!/usr/bin/env bash
# 0026: the running dev stack (bash up.sh) bounds its containers' logs, and Grafana LGTM keeps each
# signal 14 days (AC-05, AC-06, AC-07):
#
#   - AC-05: each container of the project c4-infra has json-file 10m × 3 (compose.yml's x-logging);
#   - AC-06, AC-07: in c4-infra.grafana-lgtm, Loki's /config (the compactor's retention on, the
#     filesystem delete-request store, limits_config's retention_period 2w and deletion_mode
#     disabled), /services (compactor Running), and its deletion API refusing a request (403: every
#     application's network reaches it); Prometheus' flag storage.tsdb.retention.time and
#     runtimeinfo's storageRetention, 2w; Tempo's backend_worker block_retention 336h0m0s (its
#     default too: its command line holds the flag) and its backend-scheduler and backend-worker
#     Running; Pyroscope's limits retention_period 2w, its metastore the raft leader (where the index
#     cleaner runs); a log posted by OTLP to 127.0.0.1:4318, under the tests' one service name with a
#     marker of its own in its line, read back from Loki;
#   - AC-06: c4-infra.grafana-lgtm restarted (docker restart): healthy again, every component
#     checked; the same settings; the earlier log and a new one read back.
#
#   bash tests/0026-stack-bounds.sh
#
# What each component prints is tests/0026-facts.sh's (d): an image upgrade that renames a flag or
# stops appending *_EXTRA_ARGS fails here.
#
# covers: compose.yml compose.dev.yml grafana-lgtm/ up.sh
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

LGTM=c4-infra.grafana-lgtm
BOUND='{"Type":"json-file","Config":{"max-file":"3","max-size":"10m"}}'
TEMPO_FLAG=-backend-worker.compaction.block-retention=336h
PRINTED_WEEKS=2w
PRINTED_GO=336h0m0s
# the logs the tests post: one service name, each post's marker in its line
SERVICE=c4-infra-tests

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

is() { # <actual> <expected>
  [ "$1" = "$2" ] || { echo "actual: $1, expected: $2"; return 1; }
}
running() { [ "$(docker inspect -f '{{.State.Running}}' "$1" 2> /dev/null | tr -d '\r')" = true ]; }

# AC-05
log_configs_are() { # <expected> <container>…
  local expected=$1 container actual wrong=0
  shift
  for container in "$@"; do
    actual=$(docker inspect -f '{{json .HostConfig.LogConfig}}' "$container" 2> /dev/null | tr -d '\r')
    [ "$actual" = "$expected" ] || { echo "$container: $actual"; wrong=1; }
  done
  return "$wrong"
}
mapfile -t stack < <(docker ps -a --filter label=com.docker.compose.project=c4-infra --format '{{.Names}}' | tr -d '\r' | LC_ALL=C sort)
check "AC-05: the stack's containers are listed (${#stack[@]})" test "${#stack[@]}" -ge 6
check "AC-05: each has json-file 10m × 3 (${stack[*]})" log_configs_are "$BOUND" "${stack[@]}"

check "$LGTM runs (bash up.sh)" running "$LGTM"
running "$LGTM" || finish

# The lines of a top-level section of a YAML file
section() { # <file> <key>
  awk -v key="$2:" '$0 == key { on = 1; next } /^[^ ]/ { on = 0 } on' "$1"
}
holds() { # <file> <section> <extended regex of a line>
  section "$1" "$2" | grep -E "$3" > /dev/null || { echo "$2: no line matches $3 in:"; section "$1" "$2" | grep -E 'retention|delete_request|cleanup' | head -n 10; return 1; }
}
in_lgtm() { MSYS_NO_PATHCONV=1 docker exec "$LGTM" "$@" < /dev/null | tr -d '\r'; }
# the scheduler emits the retention jobs, the worker runs them
tempo_backend_runs() {
  grep -qE '^\| backend-scheduler +\| Running \|' "$work/tempo-services" \
    && grep -qE '^\| backend-worker +\| Running \|' "$work/tempo-services" \
    || { cat "$work/tempo-services"; return 1; }
}
# each argument followed by a space
tempo_has_flag() {
  in_lgtm sh -c 'for f in /proc/[0-9]*/cmdline; do tr "\0" " " < "$f"; echo; done 2> /dev/null' \
    | grep -E '(^|/)tempo/tempo ' > "$work/tempo-cmdline"
  grep -qF -- " $TEMPO_FLAG " "$work/tempo-cmdline" || { echo "Tempo's command line: $(cat "$work/tempo-cmdline")"; return 1; }
}

# after a start, once its raft election is over (60 s at most)
pyroscope_leads() {
  local i
  for i in $(seq 60); do
    in_lgtm curl -s 127.0.0.1:4040/metrics | grep -F 'pyroscope_metastore_raft_state{state="Leader"} 1' > /dev/null && return 0
    sleep 1
  done
  in_lgtm curl -s 127.0.0.1:4040/metrics | grep -F pyroscope_metastore_raft_state
  return 1
}

# A valid request (the tests' stream, a minute of 2001), which Loki accepts (204) with deletion on
deletion_refused() {
  local code
  code=$(in_lgtm curl -s -o /dev/null -w '%{http_code}' -X POST -G --data-urlencode "query={service_name=\"$SERVICE\"}" \
    --data-urlencode start=1000000000 --data-urlencode end=1000000060 http://127.0.0.1:3100/loki/api/v1/delete)
  [ "$code" = 403 ] || { echo "POST /loki/api/v1/delete: $code"; return 1; }
}

check_settings() { # <label>
  local label=$1
  in_lgtm curl -s 127.0.0.1:3100/config > "$work/loki.yaml"
  check "$label Loki's compactor: retention_enabled: true" holds "$work/loki.yaml" compactor '^ +retention_enabled: true$'
  check "$label Loki's compactor: delete_request_store: filesystem" holds "$work/loki.yaml" compactor '^ +delete_request_store: filesystem$'
  check "$label Loki's limits_config: retention_period: $PRINTED_WEEKS" holds "$work/loki.yaml" limits_config "^ +retention_period: $PRINTED_WEEKS\$"
  check "$label Loki's limits_config: deletion_mode: disabled" holds "$work/loki.yaml" limits_config '^ +deletion_mode: disabled$'
  check "$label Loki's /services: compactor => Running" eval 'in_lgtm curl -s 127.0.0.1:3100/services | grep -x "compactor => Running" > /dev/null'
  check "$label Loki's deletion API refuses a request (POST /loki/api/v1/delete: 403)" deletion_refused
  check "$label Prometheus' flag storage.tsdb.retention.time: $PRINTED_WEEKS" \
    is "$(in_lgtm curl -s 127.0.0.1:9090/api/v1/status/flags | jq -r '.data["storage.tsdb.retention.time"]')" "$PRINTED_WEEKS"
  check "$label Prometheus' runtimeinfo storageRetention: $PRINTED_WEEKS" \
    is "$(in_lgtm curl -s 127.0.0.1:9090/api/v1/status/runtimeinfo | jq -r '.data.storageRetention')" "$PRINTED_WEEKS"
  in_lgtm curl -s 127.0.0.1:3200/status/config > "$work/tempo.yaml"
  check "$label Tempo's backend_worker: block_retention: $PRINTED_GO" holds "$work/tempo.yaml" backend_worker "^ +block_retention: $PRINTED_GO\$"
  check "$label Tempo runs with $TEMPO_FLAG (its default printed alike)" tempo_has_flag
  in_lgtm curl -s 127.0.0.1:3200/status/services > "$work/tempo-services"
  check "$label Tempo's backend-scheduler and backend-worker run" tempo_backend_runs
  in_lgtm curl -s 127.0.0.1:4040/api/v1/status/config > "$work/pyroscope.yaml"
  check "$label Pyroscope's limits: retention_period: $PRINTED_WEEKS" holds "$work/pyroscope.yaml" limits "^ +retention_period: $PRINTED_WEEKS\$"
  check "$label Pyroscope's metastore is the raft leader, where the index cleaner runs" pyroscope_leads
}

# <service name> <marker> <now> <post|read>: a log line "marker <marker>" posted by OTLP to
# 127.0.0.1:4318 (post), then read back from Loki (60 s at most)
LOG_FLOW=$(cat <<'EOF'
set -u
svc=$1 marker=$2 now=$3 mode=$4
if [ "$mode" = post ]; then
  code=$(curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' --data-binary \
    '{"resourceLogs":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"'$svc'"}}]},"scopeLogs":[{"logRecords":[{"timeUnixNano":"'$now'000000000","severityText":"INFO","body":{"stringValue":"marker '$marker'"}}]}]}]}' \
    http://127.0.0.1:4318/v1/logs)
  [ "$code" = 200 ] || { echo "POST 127.0.0.1:4318/v1/logs: $code"; exit 1; }
fi
for i in $(seq 60); do
  curl -s -G http://127.0.0.1:3100/loki/api/v1/query_range --data-urlencode "query={service_name=\"$svc\"} |= \"marker $marker\"" \
    --data-urlencode "start=$((now - 300))000000000" --data-urlencode "end=$((now + 300))000000000" > /tmp/c4-0026-read
  grep -qF "marker $marker" /tmp/c4-0026-read && exit 0
  sleep 1
done
echo "not read back after 60 s:"
head -c 600 /tmp/c4-0026-read
exit 1
EOF
)
log_flow() { # <marker> <now> <post|read>
  MSYS_NO_PATHCONV=1 docker exec -i "$LGTM" bash -s -- "$SERVICE" "$@" <<< "$LOG_FLOW"
}

# Docker's health (the image's healthcheck: a component it can't connect to is "not running
# (skipping)", and still passes), every component checked, Pyroscope (outside it) ready
healthy() {
  local output
  [ "$(docker inspect -f '{{.State.Health.Status}}' "$LGTM" 2> /dev/null | tr -d '\r')" = healthy ] || return 1
  output=$(MSYS_NO_PATHCONV=1 docker exec "$LGTM" /otel-lgtm/docker/healthcheck.sh < /dev/null 2>&1) || return 1
  [[ $output != *"not running"* && $output == *"All running services healthy"* ]] || return 1
  [ "$(in_lgtm curl -s -o /dev/null -w '%{http_code}' 127.0.0.1:4040/ready)" = 200 ]
}

check_settings "AC-06, AC-07:"
first_marker=$(openssl rand -hex 8)
first_now=$(date +%s)
check "AC-06: a log posted to 127.0.0.1:4318 is read back from Loki" log_flow "$first_marker" "$first_now" post

docker restart "$LGTM" > /dev/null
waited=0
until healthy; do
  if [ "$waited" -ge 300 ] || ! running "$LGTM"; then
    break
  fi
  sleep 1
  waited=$((waited + 1))
done
healthy_again() {
  healthy || {
    docker inspect -f '{{.State.Health.Status}}' "$LGTM"
    MSYS_NO_PATHCONV=1 docker exec "$LGTM" /otel-lgtm/docker/healthcheck.sh < /dev/null 2>&1
    return 1
  }
}
check "AC-06: $LGTM restarted, healthy again, every component checked (after ${waited} s)" healthy_again
check_settings "AC-06 (restarted):"
check "AC-06: the earlier log is read back from Loki" log_flow "$first_marker" "$first_now" read
second_marker=$(openssl rand -hex 8)
check "AC-06: a new log posted to 127.0.0.1:4318 is read back from Loki" log_flow "$second_marker" "$(date +%s)" post
finish
