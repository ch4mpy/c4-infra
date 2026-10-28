#!/usr/bin/env bash
# 0001: the dev stack publishes its ports on the loopback only (RQ-01, AC-01), and up.sh refuses to
# start when host.docker.internal resolves elsewhere (RQ-04, AC-05).
#
#   bash tests/0001-loopback-ports.sh [config|running|resolution]...   (every part by default)
#
#   config      the compose model: every published port on 127.0.0.1, and the nine of RQ-01 there
#   running     the running stack (started by up.sh): every mapping of a c4-infra container on
#               127.0.0.1
#   resolution  up.sh with fake docker, getent and powershell.exe: answering a LAN address, it stops,
#               says how to fix it and calls no docker; answering 127.0.0.1, it gets past the check
#
# covers: up.sh env.sh compose.yml compose.dev.yml
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/stubs.sh

# RQ-01: every port the dev stack publishes
PORTS=(80 443 1025 8025 5672 15672 3000 4317 4318)
LAN_ADDRESS=192.168.1.20

# "<published> <host_ip>" for each port compose.yml publishes ("none" when it names no address)
published_ports() {
  docker compose config --format json \
    | jq -r '.services[] | (.ports // [])[] | "\(.published) \(.host_ip // "none")"'
}

is_listed() { # <port> <published_ports output>
  grep -q "^$1 " <<< "$2" || { echo "not in compose.yml's published ports"; return 1; }
}

part_config() {
  local ports published host_ip port
  ports=$(published_ports)
  check "docker compose config lists published ports" test -n "$ports"
  while read -r published host_ip; do
    [ -n "$published" ] || continue
    check "port $published is published on 127.0.0.1 (host_ip: $host_ip)" test "$host_ip" = 127.0.0.1
  done <<< "$ports"
  for port in "${PORTS[@]}"; do
    check "port $port is published" is_listed "$port" "$ports"
  done
}

# "<container> <mapping>" for each published port of the running c4-infra containers, where a
# mapping is docker's "<ip>:<port>-><port>/<protocol>"
running_mappings() {
  local name ports
  docker ps --filter 'name=^c4-infra\.' --format '{{.Names}} {{.Ports}}' \
    | while read -r name ports; do
        tr ',' '\n' <<< "$ports" | sed 's/^ *//' | grep -F -- '->' | sed "s/^/$name /"
      done
}

on_loopback() { # <mapping>
  case "$1" in
    127.0.0.1:*) ;;
    *) echo "bound to ${1%%:[0-9]*}"; return 1 ;;
  esac
}

part_running() {
  local mappings name mapping
  mappings=$(running_mappings)
  check "the running stack publishes ports (started by up.sh)" test -n "$mappings"
  while read -r name mapping; do
    [ -n "$name" ] || continue
    check "$name publishes $mapping on 127.0.0.1" on_loopback "$mapping"
  done <<< "$mappings"
}

# Runs up.sh with the fakes of <dir> answering <address>: sets up_status, and leaves its stdout,
# its stderr and the fake docker's log in <dir>/up.out, <dir>/up.err and <dir>/docker.log
run_up() { # <dir> <address>
  : > "$1/docker.log"
  STUB_LOG="$1/docker.log" STUB_ADDRESS=$2 PATH="$1:$PATH" bash ./up.sh > "$1/up.out" 2> "$1/up.err"
  up_status=$?
}

exited_non_zero() {
  [ "$up_status" -ne 0 ] || { echo "up.sh exited 0"; return 1; }
}

says() { # <dir> <text>: up.sh's stderr holds the text
  grep -qF -- "$2" "$1/up.err" || { echo "up.sh's stderr:"; tail -n 5 "$1/up.err"; return 1; }
}

called_no_docker() { # <dir>
  [ ! -s "$1/docker.log" ] || { echo "up.sh called:"; head -n 5 "$1/docker.log"; return 1; }
}

called_docker_compose() { # <dir>
  grep -q '^docker compose ' "$1/docker.log" \
    || { echo "up.sh exited $up_status, its stderr:"; tail -n 5 "$1/up.err"; return 1; }
}

resolution_variant() { # <label> <dir with the fakes>
  local label=$1 dir=$2
  run_up "$dir" "$LAN_ADDRESS"
  check "$label, $LAN_ADDRESS: up.sh stops" exited_non_zero
  check "$label, $LAN_ADDRESS: its message names $LAN_ADDRESS" says "$dir" "$LAN_ADDRESS"
  check "$label, $LAN_ADDRESS: its message gives the hosts-file line" says "$dir" '127.0.0.1 host.docker.internal'
  check "$label, $LAN_ADDRESS: its message names Docker Desktop's option" \
    says "$dir" "Add the *.docker.internal names to the host's etc/hosts file"
  check "$label, $LAN_ADDRESS: up.sh starts nothing (no docker call)" called_no_docker "$dir"

  run_up "$dir" 127.0.0.1
  check "$label, 127.0.0.1: up.sh gets past the check (docker compose called)" called_docker_compose "$dir"
}

part_resolution() {
  stubs=$(mktemp -d)
  trap 'rm -rf "$stubs"' EXIT
  # up.sh asks getent when there is one
  if command -v getent > /dev/null; then
    echo "skip - PowerShell branch: this machine has a getent, which up.sh asks first"
  else
    stub_path "$stubs/powershell" docker powershell.exe
    resolution_variant "PowerShell branch" "$stubs/powershell"
  fi
  stub_path "$stubs/getent" docker getent powershell.exe
  resolution_variant "getent branch" "$stubs/getent"
}

[ $# -gt 0 ] || set -- config running resolution
for part in "$@"; do
  case "$part" in
    config | running | resolution)
      echo "# $part"
      "part_$part"
      ;;
    *)
      echo "Unknown part: $part (config, running or resolution)" >&2
      exit 2
      ;;
  esac
done
finish
