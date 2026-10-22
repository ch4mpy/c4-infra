#!/usr/bin/env bash
# 0007: Grafana LGTM's internal ports on its container's loopback, its components still working
# together (REQ-11, AC-12).
#
#   bash tests/0007-lgtm.sh [throwaway|running]...   (every part by default)
#
#   throwaway  a container of grafana-lgtm's image, publishing no port, with the environment and the
#              bind mount that `docker compose config` gives grafana-lgtm (its data on an anonymous
#              volume); once run-all.sh reports every component up:
#                (a) its listening sockets (/proc/net/tcp, /proc/net/tcp6): 7946, 9095, 9096, 9097
#                    and 13133 on 127.0.0.1 only, and on every interface exactly 3000, 3100, 3200,
#                    4040, 4317, 4318 and 9090;
#                (b) a log, a trace and a metric posted to 127.0.0.1:4318 (OTLP/HTTP), and a profile
#                    posted to 127.0.0.1:4040/ingest, each read back: Loki's query_range, Tempo's
#                    /api/traces/<id>, Prometheus' /api/v1/query, Pyroscope's
#                    querier.v1.QuerierService/SelectMergeStacktraces (with a time range); Grafana's
#                    /api/datasources lists Loki, Tempo, Prometheus and Pyroscope;
#                (c) the image's healthcheck passes, every component checked (none "not running");
#                (d) grafana-lgtm/tempo-config.yaml, without its leading comment and the added
#                    grpc_listen_address line, is the image's own /otel-lgtm/tempo-config.yaml
#   running    (a) and (c) against the running c4-infra.grafana-lgtm (bash up.sh), healthy
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

THROWAWAY=c4probe-lgtm
INTERNAL_PORTS=(7946 9095 9096 9097 13133)
# what an application's network reaches (README, "Reachable from an application's network")
PUBLIC_PORTS='3000 3100 3200 4040 4317 4318 9090'
ADDED_LINE='  grpc_listen_address: 127.0.0.1'

host_path() {
  if command -v cygpath > /dev/null; then cygpath -w "$1"; else printf '%s' "$1"; fi
}

work=$(mktemp -d)
cleanup() {
  docker rm -f -v "$THROWAWAY" > /dev/null 2>&1
  rm -rf "$work"
}
trap cleanup EXIT

# "<address> <port>" of each listening TCP socket of the container (IPv4 and IPv6)
listeners() { # <container>
  local sl local_address rest port address
  MSYS_NO_PATHCONV=1 docker exec "$1" cat /proc/net/tcp /proc/net/tcp6 < /dev/null | tr -d '\r' \
    | while read -r sl local_address _ st rest; do
        [ "$st" = 0A ] || continue
        address=${local_address%:*}
        port=$((16#${local_address##*:}))
        case $address in
          00000000) address=0.0.0.0 ;;
          00000000000000000000000000000000) address=:: ;;
          00000000000000000000000001000000) address=::1 ;;
          0000000000000000FFFF0000????????)
            address=${address:24}
            address=::ffff:$((16#${address:6:2})).$((16#${address:4:2})).$((16#${address:2:2})).$((16#${address:0:2}))
            ;;
          ????????) address=$((16#${address:6:2})).$((16#${address:4:2})).$((16#${address:2:2})).$((16#${address:0:2})) ;;
        esac
        echo "$address $port"
      done
}
# the addresses <port> listens on, sorted, on one line
addresses_of_port() { # <listeners file> <port>
  awk -v port="$2" '$2 == port { print $1 }' "$1" | sort -u | paste -sd' ' -
}
# the ports listening elsewhere than on the loopback, sorted, on one line
public_ports() { # <listeners file>
  awk '$1 !~ /^127\./ && $1 != "::1" && $1 !~ /^::ffff:127\./ { print $2 }' "$1" | sort -n -u | paste -sd' ' -
}

# (a)
check_listeners() { # <container>
  local container=$1 port found
  listeners "$container" > "$work/listeners"
  check "$container: its listening sockets are read ($(wc -l < "$work/listeners"))" test -s "$work/listeners"
  for port in "${INTERNAL_PORTS[@]}"; do
    found=$(addresses_of_port "$work/listeners" "$port")
    check "$container: $port listens on 127.0.0.1 only (${found:-not listening})" test "$found" = 127.0.0.1
  done
  found=$(public_ports "$work/listeners")
  check "$container: on every interface exactly $PUBLIC_PORTS (${found:-none})" test "$found" = "$PUBLIC_PORTS"
}

# (c)
healthcheck_passes() { # <container>
  local output
  output=$(MSYS_NO_PATHCONV=1 docker exec "$1" /otel-lgtm/docker/healthcheck.sh < /dev/null 2>&1) \
    || { printf '%s\n' "$output"; return 1; }
  # a component the script can't connect to is "not running (skipping)", and still passes
  if [[ $output == *"not running"* ]] || [[ $output != *"All running services healthy"* ]]; then
    printf '%s\n' "$output"
    return 1
  fi
}

part_throwaway() {
  local config image waited=0 svc trace now signal
  config=$(docker compose config --format json) || { check "docker compose config succeeds" false; return; }
  image=$(jq -r '.services["grafana-lgtm"].image' <<< "$config")
  check "grafana-lgtm's image is $image" test -n "$image"
  jq -r '.services["grafana-lgtm"].environment // {} | to_entries[] | "\(.key)=\(.value)"' <<< "$config" > "$work/env"
  check "grafana-lgtm's environment holds TEMPO_EXTRA_ARGS (the copy of Tempo's file)" grep -q '^TEMPO_EXTRA_ARGS=-config.file=' "$work/env"
  local mounts=()
  while IFS=$'\t' read -r type source target read_only; do
    case $type in
      bind)
        mounts+=(--mount "type=bind,source=$source,target=$target$([ "$read_only" = true ] && echo ,readonly)") ;;
      volume)
        mounts+=(--mount "type=volume,target=$target") ;;
    esac
  # (a string, not @tsv: @tsv doubles the backslashes of a Windows path)
  done < <(jq -r '.services["grafana-lgtm"].volumes // [] | .[] | "\(.type)\t\(.source // "")\t\(.target)\t\(.read_only // false)"' <<< "$config")
  docker rm -f -v "$THROWAWAY" > /dev/null 2>&1
  MSYS_NO_PATHCONV=1 docker run -d --name "$THROWAWAY" --env-file "$(host_path "$work/env")" "${mounts[@]}" "$image" > /dev/null
  check "a throwaway $image starts ($THROWAWAY, no published port)" \
    test "$(docker inspect -f '{{.State.Running}}' "$THROWAWAY" 2> /dev/null)" = true
  until MSYS_NO_PATHCONV=1 docker exec "$THROWAWAY" test -f /tmp/ready < /dev/null 2> /dev/null; do
    if [ "$waited" -ge 300 ] || [ "$(docker inspect -f '{{.State.Running}}' "$THROWAWAY" 2> /dev/null)" != true ]; then
      break
    fi
    sleep 1
    waited=$((waited + 1))
  done
  ready() {
    MSYS_NO_PATHCONV=1 docker exec "$THROWAWAY" test -f /tmp/ready < /dev/null \
      || { docker logs --tail 20 "$THROWAWAY" 2>&1; return 1; }
  }
  check "run-all.sh reports every component up (/tmp/ready, after ${waited} s)" ready

  # (a)
  check_listeners "$THROWAWAY"

  # (b): in the container, on its loopback; the payloads name a service of their own
  svc=c4-infra-0007-$(openssl rand -hex 4)
  trace=$(openssl rand -hex 16)
  now=$(date +%s)
  cat > "$work/flow.sh" <<'EOF'
# <signal> <service name> <trace id> <now, in seconds>: posts it, then reads it back (60 s at most)
set -u
signal=$1 svc=$2 trace=$3 now=$4
ns=${now}000000000
resource='{"attributes":[{"key":"service.name","value":{"stringValue":"'$svc'"}}]}'
otlp() { # <signal path> <payload>
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' --data-binary "$2" "http://127.0.0.1:4318/v1/$1")
  [ "$code" = 200 ] || { echo "POST 127.0.0.1:4318/v1/$1: $code"; exit 1; }
}
poll() { # <command…>: until it succeeds, 60 s at most; then shows what it read
  local i
  for i in $(seq 60); do
    "$@" > /tmp/c4probe-read 2>&1 && return 0
    sleep 1
  done
  echo "not read back after 60 s:"
  head -c 600 /tmp/c4probe-read
  echo
  return 1
}
loki() {
  curl -s -G http://127.0.0.1:3100/loki/api/v1/query_range --data-urlencode "query={service_name=\"$svc\"}" \
    --data-urlencode "start=$((now - 300))000000000" --data-urlencode "end=$((now + 300))000000000" | tee /dev/stderr \
    | grep -qF "marker $svc"
}
tempo() {
  curl -s "http://127.0.0.1:3200/api/traces/$trace" | tee /dev/stderr | grep -qF "probe-$svc"
}
prometheus() {
  curl -s -G http://127.0.0.1:9090/api/v1/query --data-urlencode "query=c4_infra_0007_probe{service_name=\"$svc\"}" \
    | tee /dev/stderr | grep -qF ',"7"]'
}
pyroscope() {
  local answer
  answer=$(curl -s -X POST -H 'Content-Type: application/json' http://127.0.0.1:4040/querier.v1.QuerierService/SelectMergeStacktraces \
    -d '{"profileTypeID":"process_cpu:cpu:nanoseconds:cpu:nanoseconds","labelSelector":"{service_name=\"'$svc'\"}","start":'$(((now - 300) * 1000))',"end":'$(((now + 300) * 1000))'}')
  echo "$answer" >&2
  [[ $answer == *'"probe"'* && $answer == *'"idle"'* ]]
}
case $signal in
  log)
    otlp logs '{"resourceLogs":[{"resource":'"$resource"',"scopeLogs":[{"logRecords":[{"timeUnixNano":"'$ns'","severityText":"INFO","body":{"stringValue":"marker '$svc'"}}]}]}]}'
    poll loki
    ;;
  trace)
    otlp traces '{"resourceSpans":[{"resource":'"$resource"',"scopeSpans":[{"spans":[{"traceId":"'$trace'","spanId":"'${trace:0:16}'","name":"probe-'$svc'","kind":1,"startTimeUnixNano":"'$ns'","endTimeUnixNano":"'$((now + 1))'000000000"}]}]}]}'
    poll tempo
    ;;
  metric)
    otlp metrics '{"resourceMetrics":[{"resource":'"$resource"',"scopeMetrics":[{"metrics":[{"name":"c4_infra_0007_probe","gauge":{"dataPoints":[{"asDouble":7,"timeUnixNano":"'$ns'"}]}}]}]}]}'
    poll prometheus
    ;;
  profile)
    # the folded format: one stack per line, its sample count last
    code=$(printf 'main;work;probe 100\nmain;idle 50\n' | curl -s -o /dev/null -w '%{http_code}' --data-binary @- \
      "http://127.0.0.1:4040/ingest?name=$svc.cpu&from=$((now - 10))&until=$now&format=folded&sampleRate=100&spyName=probe")
    [ "$code" = 200 ] || { echo "POST 127.0.0.1:4040/ingest: $code"; exit 1; }
    poll pyroscope
    ;;
  datasources)
    answer=$(curl -s http://127.0.0.1:3000/api/datasources)
    for type in loki tempo prometheus grafana-pyroscope-datasource; do
      [[ $answer == *"\"type\":\"$type\""* ]] || { echo "no data source of type $type: $(echo "$answer" | head -c 400)"; exit 1; }
    done
    ;;
esac
EOF
  flow() { # <signal>
    MSYS_NO_PATHCONV=1 docker exec -i "$THROWAWAY" bash -s -- "$1" "$svc" "$trace" "$now" < "$work/flow.sh" 2> /dev/null
  }
  check "(b) a log posted to 127.0.0.1:4318 is read back from Loki" flow log
  check "(b) a trace posted to 127.0.0.1:4318 is read back from Tempo" flow trace
  check "(b) a metric posted to 127.0.0.1:4318 is read back from Prometheus" flow metric
  check "(b) a profile posted to 127.0.0.1:4040/ingest is read back from Pyroscope" flow profile
  check "(b) Grafana lists the Loki, Tempo, Prometheus and Pyroscope data sources" flow datasources

  # (c)
  check "(c) the image's healthcheck passes, every component checked" healthcheck_passes "$THROWAWAY"

  # (d)
  MSYS_NO_PATHCONV=1 docker run --rm --entrypoint cat "$image" /otel-lgtm/tempo-config.yaml < /dev/null | tr -d '\r' > "$work/image-tempo.yaml"
  sed -n '/^[^#]/,$p' grafana-lgtm/tempo-config.yaml | tr -d '\r' | grep -vxF -- "$ADDED_LINE" > "$work/copy-tempo.yaml"
  check "(d) grafana-lgtm/tempo-config.yaml adds $ADDED_LINE" grep -qxF -- "$ADDED_LINE" grafana-lgtm/tempo-config.yaml
  check "(d) the image's tempo-config.yaml is read ($image)" test -s "$work/image-tempo.yaml"
  check "(d) and grafana-lgtm/tempo-config.yaml is that file otherwise" diff "$work/image-tempo.yaml" "$work/copy-tempo.yaml"
  docker rm -f -v "$THROWAWAY" > /dev/null 2>&1
}

part_running() {
  local container=c4-infra.grafana-lgtm
  check "$container runs (bash up.sh)" test "$(docker inspect -f '{{.State.Running}}' "$container" 2> /dev/null)" = true
  check_listeners "$container"
  check "(c) $container: the image's healthcheck passes, every component checked" healthcheck_passes "$container"
  check "$container is healthy" test "$(docker inspect -f '{{.State.Health.Status}}' "$container" 2> /dev/null)" = healthy
}

[ $# -gt 0 ] || set -- throwaway running
for part in "$@"; do
  case "$part" in
    throwaway | running)
      echo "# $part"
      "part_$part"
      ;;
    *)
      echo "Unknown part: $part (throwaway or running)" >&2
      exit 2
      ;;
  esac
done
finish
