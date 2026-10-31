#!/usr/bin/env bash
# 0026: the facts the bound on the containers' logs and the stack's retentions rest on, on this
# machine's Docker:
#
#   bash tests/0026-facts.sh [docker|lgtm]...   (every part by default)
#
#   docker  (a) compose recreates a container whose service changes only by `logging` (json-file
#               10m × 3 added: a new id, that LogConfig), and leaves it alone at the next identical up;
#           (b) `docker compose -p <project> logs --tail 1 --no-log-prefix`, run from a directory
#               without a compose file, shows the project's last line; so does `docker logs --tail 1`;
#           (c) under json-file 10m × 3, a container printing 60 MiB of 1 KiB lines: `docker logs`
#               ends on its last line, lacks its first, holds at most 30 MiB
#   lgtm    (d) a throwaway of grafana-lgtm's image (no published port, an anonymous volume,
#               grafana-lgtm/ mounted as compose.yml does), with compose.yml's environment, its
#               retention flags as they are: every component up; Loki's /config (retention on, its
#               period, the filesystem delete-request store, deletion_mode disabled), /services
#               (compactor Running), and its deletion API refusing a valid request (403); Prometheus'
#               flag and runtimeinfo; Tempo's /status/config (backend_worker's block_retention) and
#               /status/services (backend-scheduler and backend-worker Running), and a Tempo alone
#               given the flag at another value than its default printing it; Pyroscope's
#               /api/v1/status/config (limits' retention_period, the metastore's cleanup interval)
#               and its metastore the raft leader (the index cleaner runs on the leader); a log
#               posted by OTLP (the tests' service name, a marker of its own) and read back from Loki;
#           (e) the throwaway restarted, healthy again (the image's healthcheck, every component
#               checked: /tmp/ready survives a restart), Pyroscope ready: the same settings, the
#               earlier log and a new one read back
#
# Its projects and containers are removed whatever happens.
#
# covers: compose.yml grafana-lgtm/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/docker-preflight.sh
mapfile -t C4_LABELS < <(docker_labels c4-infra)
COMPOSE_LABELS="{c4-infra.owner: c4-infra, c4-infra.run: \"$C4_INFRA_RUN\", c4-infra.created: \"$(date +%s)\", c4-infra.ttl: \"14400\", c4-infra.lock: \"${C4_DOCKER_LOCK:-}\"}"

CADDY_IMAGE=caddy:2.11.4-alpine
STILL_PROJECT=c4-infra-0026-facts-still
TALKER_PROJECT=c4-infra-0026-facts-talker
STILL=c4-infra.0026-facts-still
TALKER=c4-infra.0026-facts-talker
LGTM=c4-infra.0026-facts-lgtm
TEMPO=c4-infra.0026-facts-tempo
BOUND='{"Type":"json-file","Config":{"max-file":"3","max-size":"10m"}}'
# the logs the tests post: one service name, each post's marker in its line
SERVICE=c4-infra-tests
# how each component prints 336h
PRINTED_WEEKS=2w
PRINTED_GO=336h0m0s

host_path() { if command -v cygpath > /dev/null; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

work=$(mktemp -d)
cleanup() {
  docker rm -f -v "$LGTM" "$TEMPO" > /dev/null 2>&1
  (cd "$work/empty" && docker compose -p "$STILL_PROJECT" down -t 0 > /dev/null 2>&1)
  (cd "$work/empty" && docker compose -p "$TALKER_PROJECT" down -t 0 > /dev/null 2>&1)
  rm -rf "$work"
}
trap cleanup EXIT
mkdir -p "$work/empty"

is() { # <actual> <expected>
  [ "$1" = "$2" ] || { echo "actual: $1, expected: $2"; return 1; }
}
id_of() { docker inspect -f '{{.Id}}' "$1" 2> /dev/null | tr -d '\r'; }
log_config() { docker inspect -f '{{json .HostConfig.LogConfig}}' "$1" 2> /dev/null | tr -d '\r'; }

part_docker() {
  local first second third last size
  # (a) one service, then the same with the bound only
  cat > "$work/still.yml" <<EOF
networks:
  default: {labels: $COMPOSE_LABELS}
services:
  still:
    image: $CADDY_IMAGE
    container_name: $STILL
    labels: $COMPOSE_LABELS
    command: [caddy, respond, --listen, ':7080', facts]
EOF
  { cat "$work/still.yml"; printf '    logging:\n      driver: json-file\n      options:\n        max-size: 10m\n        max-file: "3"\n'; } > "$work/still-bounded.yml"
  still_up() { docker compose -p "$STILL_PROJECT" -f "$(host_path "$work/$1")" up -d > "$work/still-up.log" 2>&1 || { cat "$work/still-up.log"; return 1; }; }
  check "(a) a service without logging comes up ($STILL)" still_up still.yml
  first=$(id_of "$STILL")
  echo "# (a) its LogConfig, the daemon's default: $(log_config "$STILL")"
  check "(a) the same service with logging json-file 10m × 3 only: up exits 0" still_up still-bounded.yml
  second=$(id_of "$STILL")
  check "(a) the container is recreated (a new id)" eval '[ -n "$first" ] && [ -n "$second" ] && [ "$first" != "$second" ]'
  check "(a) with that LogConfig" is "$(log_config "$STILL")" "$BOUND"
  check "(a) the same file again: up exits 0" still_up still-bounded.yml
  third=$(id_of "$STILL")
  check "(a) the container is left alone (the same id)" is "$third" "$second"

  # (b), (c) a bounded container printing 60 MiB, a line apart first and last
  cat > "$work/talker.yml" <<EOF
networks:
  default: {labels: $COMPOSE_LABELS}
services:
  talker:
    image: $CADDY_IMAGE
    container_name: $TALKER
    labels: $COMPOSE_LABELS
    init: true
    logging:
      driver: json-file
      options:
        max-size: 10m
        max-file: "3"
    command:
      - sh
      - -c
      - |
        echo first-line
        line=\$\$(printf '%01023d' 0)
        yes "\$\$line" | head -n 61440
        echo last-line
        exec sleep 3600
EOF
  docker compose -p "$TALKER_PROJECT" -f "$(host_path "$work/talker.yml")" up -d > "$work/talker-up.log" 2>&1
  check "(b) a container printing 60 MiB of 1 KiB lines comes up ($TALKER)" test -n "$(id_of "$TALKER")"
  printed() { # 60 s at most
    local i
    for i in $(seq 60); do
      [ "$(docker logs --tail 1 "$TALKER" 2> /dev/null | tr -d '\r')" = last-line ] && return 0
      sleep 1
    done
    echo "its last line: $(docker logs --tail 1 "$TALKER" 2>&1 | head -c 200)"
    return 1
  }
  check "(b) docker logs --tail 1 shows its last line" printed
  last=$(cd "$work/empty" && docker compose -p "$TALKER_PROJECT" logs --tail 1 --no-log-prefix talker 2>&1 | tr -d '\r')
  check "(b) so does docker compose -p $TALKER_PROJECT logs --tail 1 --no-log-prefix, from a directory without a compose file" \
    is "$last" last-line
  docker logs "$TALKER" > "$work/talker.log" 2>&1
  size=$(wc -c < "$work/talker.log" | tr -d ' ')
  echo "# (c) docker logs holds $size bytes, $(wc -l < "$work/talker.log" | tr -d ' ') lines"
  check "(c) docker logs ends on its last line" is "$(tail -n 1 "$work/talker.log")" last-line
  check "(c) and lacks its first" eval '[ "$(head -n 1 "$work/talker.log")" != first-line ]'
  check "(c) at most 30 MiB ($size bytes)" test "$size" -le $((30 * 1024 * 1024))
}

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
  in_lgtm curl -s 127.0.0.1:3200/status/services > "$work/tempo-services"
  check "$label Tempo's backend-scheduler and backend-worker run in the single binary" tempo_backend_runs
  in_lgtm curl -s 127.0.0.1:4040/api/v1/status/config > "$work/pyroscope.yaml"
  check "$label Pyroscope's limits: retention_period: $PRINTED_WEEKS" holds "$work/pyroscope.yaml" limits "^ +retention_period: $PRINTED_WEEKS\$"
  check "$label Pyroscope's metastore cleans its index (cleanup_interval not 0s)" holds "$work/pyroscope.yaml" metastore '^ +cleanup_interval: [1-9]'
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

healthy() {
  local output
  output=$(MSYS_NO_PATHCONV=1 docker exec "$LGTM" /otel-lgtm/docker/healthcheck.sh < /dev/null 2>&1) || return 1
  # a component the script can't connect to is "not running (skipping)", and still passes
  [[ $output != *"not running"* && $output == *"All running services healthy"* ]] || return 1
  [ "$(in_lgtm curl -s -o /dev/null -w '%{http_code}' 127.0.0.1:4040/ready)" = 200 ]
}

part_lgtm() {
  local config image waited first_marker second_marker first_now
  config=$(docker compose -f compose.yml config --format json) || { check "docker compose -f compose.yml config succeeds" false; return; }
  image=$(jq -r '.services["grafana-lgtm"].image' <<< "$config")
  jq -r '.services["grafana-lgtm"].environment // {} | to_entries[] | "\(.key)=\(.value)"' <<< "$config" > "$work/env"
  local mounts=()
  while IFS=$'\t' read -r type source target read_only; do
    case $type in
      bind) mounts+=(--mount "type=bind,source=$source,target=$target$([ "$read_only" = true ] && echo ,readonly)") ;;
      volume) mounts+=(--mount "type=volume,target=$target") ;;
    esac
  # (a string, not @tsv: @tsv doubles the backslashes of a Windows path)
  done < <(jq -r '.services["grafana-lgtm"].volumes // [] | .[] | "\(.type)\t\(.source // "")\t\(.target)\t\(.read_only // false)"' <<< "$config")
  docker rm -f -v "$LGTM" > /dev/null 2>&1
  MSYS_NO_PATHCONV=1 docker run "${C4_LABELS[@]}" -d --name "$LGTM" --env-file "$(host_path "$work/env")" "${mounts[@]}" "$image" > /dev/null
  check "(d) a throwaway $image starts ($LGTM, no published port)" \
    test "$(docker inspect -f '{{.State.Running}}' "$LGTM" 2> /dev/null)" = true
  waited=0
  until MSYS_NO_PATHCONV=1 docker exec "$LGTM" test -f /tmp/ready < /dev/null 2> /dev/null; do
    if [ "$waited" -ge 300 ] || [ "$(docker inspect -f '{{.State.Running}}' "$LGTM" 2> /dev/null)" != true ]; then
      break
    fi
    sleep 1
    waited=$((waited + 1))
  done
  ready() {
    MSYS_NO_PATHCONV=1 docker exec "$LGTM" test -f /tmp/ready < /dev/null \
      || { docker logs --tail 20 "$LGTM" 2>&1; return 1; }
  }
  check "(d) every component up (/tmp/ready, after ${waited} s)" ready
  check_settings "(d)"

  # Tempo prints its default, 336h0m0s, for the flag's value: the flag at another value, in a Tempo alone
  MSYS_NO_PATHCONV=1 docker run "${C4_LABELS[@]}" -d --name "$TEMPO" --entrypoint /otel-lgtm/tempo/tempo "$image" \
    -config.file=/otel-lgtm/tempo-config.yaml -backend-worker.compaction.block-retention=335h > /dev/null
  tempo_alone() {
    local i
    for i in $(seq 60); do
      MSYS_NO_PATHCONV=1 docker exec "$TEMPO" curl -s 127.0.0.1:3200/status/config < /dev/null 2> /dev/null | tr -d '\r' > "$work/tempo-alone.yaml"
      [ -s "$work/tempo-alone.yaml" ] && break
      sleep 1
    done
    holds "$work/tempo-alone.yaml" backend_worker '^ +block_retention: 335h0m0s$'
  }
  check "(d) -backend-worker.compaction.block-retention sets it: a Tempo alone, the flag at 335h, prints 335h0m0s" tempo_alone
  docker rm -f -v "$TEMPO" > /dev/null 2>&1

  first_marker=$(openssl rand -hex 8)
  first_now=$(date +%s)
  check "(d) a log posted to 127.0.0.1:4318 is read back from Loki" log_flow "$first_marker" "$first_now" post

  # (e)
  docker restart "$LGTM" > /dev/null
  waited=0
  until healthy; do
    if [ "$waited" -ge 300 ] || [ "$(docker inspect -f '{{.State.Running}}' "$LGTM" 2> /dev/null)" != true ]; then
      break
    fi
    sleep 1
    waited=$((waited + 1))
  done
  healthy_again() {
    healthy || { MSYS_NO_PATHCONV=1 docker exec "$LGTM" /otel-lgtm/docker/healthcheck.sh < /dev/null 2>&1; docker logs --tail 20 "$LGTM" 2>&1; return 1; }
  }
  check "(e) restarted, healthy again: every component checked, Pyroscope ready (after ${waited} s)" healthy_again
  check_settings "(e)"
  check "(e) the earlier log is read back from Loki" log_flow "$first_marker" "$first_now" read
  second_marker=$(openssl rand -hex 8)
  check "(e) a new log posted to 127.0.0.1:4318 is read back from Loki" log_flow "$second_marker" "$(date +%s)" post
  docker rm -f -v "$LGTM" > /dev/null 2>&1
}

[ $# -gt 0 ] || set -- docker lgtm
for part in "$@"; do
  case "$part" in
    docker | lgtm)
      echo "# $part"
      "part_$part"
      ;;
    *)
      echo "Unknown part: $part (docker or lgtm)" >&2
      exit 2
      ;;
  esac
done
finish
