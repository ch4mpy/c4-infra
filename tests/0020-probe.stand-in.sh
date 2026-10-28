#!/usr/bin/env bash
# 0020: the isolation tests' probe (tests/fixtures/0007/probe/) reaches the stand-in's Docker even when
# the stand-in resolves no name: its resolver pointed at 192.0.2.1 (TEST-NET-1, which answers nothing;
# Docker would replace 127.0.0.1 by a public resolver), then stand_in_probe; c4-test/probe is in the
# stand-in's Docker and a container of it answers on :7080.
#
#   bash tests/0020-probe.stand-in.sh
#
# The stand-in is removed at the end (stand_in_down), its resolver with it.
#
# covers: tests/fixtures/0007/probe/ tests/stand-in-host/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/stand-in-host.sh

trap 'stand_in_down' EXIT

no_resolver() { # and no probe left from an earlier run in the stand-in's volume
  stand_in_exec sh -c 'echo "nameserver 192.0.2.1" > /etc/resolv.conf && docker image rm -f c4-test/probe > /dev/null'
}

answers() { # a container of the probe, as the isolation tests run it, answers on :7080
  local body i
  stand_in_exec docker rm -f probe-0020 > /dev/null 2>&1
  stand_in_exec docker run -d --name probe-0020 c4-test/probe > /dev/null || return 1
  for ((i = 0; i < 20; i++)); do
    body=$(stand_in_exec docker exec probe-0020 wget -qO- http://127.0.0.1:7080/ 2> /dev/null | tr -d '\r')
    [ "$body" = probe ] && return 0
    sleep 0.5
  done
  echo "answer: ${body:-none}"
  return 1
}

check "the stand-in host starts" stand_in_up
check "its resolver answers nothing (192.0.2.1)" no_resolver
check "the probe image reaches the stand-in's Docker (stand_in_probe)" stand_in_probe
check "a container of it answers on :7080" answers
finish
