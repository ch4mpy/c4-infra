#!/usr/bin/env bash
# 0037 on a Linux Docker (AC-07): tests/0037-queue.sh run inside a stand-in host (Ubuntu, bash, its
# own dockerd, whose clock orders the queue), with alpine:3 loaded from this machine and the files the
# test reads copied in.
#
#   bash tests/0037-queue-linux.stand-in.sh      (bash tests/run.sh --all runs it)
#
# covers: tests/lib/suite-lock.sh tests/0037-queue.sh tests/fixtures/0037/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/stand-in-host.sh

DIR=/root/c4-infra-0037
trap stand_in_down EXIT

copy_in() { # the test and what it reads, into $DIR
  tar -cf - tests/lib/assert.sh tests/lib/suite-lock.sh tests/0037-queue.sh tests/fixtures/0037 CLAUDE.md \
    | stand_in_exec -i sh -c 'mkdir -p "$1" && tar -xf - -C "$1"' sh "$DIR"
}

check "the stand-in host starts" stand_in_up
check "alpine:3 is loaded into it" stand_in_load_image alpine:3
stand_in_exec rm -rf "$DIR"
check "the test and what it reads are copied in" copy_in
output=$(stand_in_exec bash -c 'cd "$1" && bash tests/0037-queue.sh < /dev/null' sh "$DIR" 2>&1)
printf '%s\n' "$output" | sed 's/^/  | /'
check "tests/0037-queue.sh passes on the stand-in's Linux Docker" grep -qx 'every check passed' <<< "$output"
finish
