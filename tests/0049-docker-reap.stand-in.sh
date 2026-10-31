#!/usr/bin/env bash
# 0049: tests/lib/docker-preflight.sh's reaper on what it may and may not remove, inside a stand-in's
# own Docker, never the host's: the library copied in and run there by bash as the lock's holder
# (C4_INFRA_RUN=mine, C4_DOCKER_LOCK=the-lock), a pins file naming c4-test/pinned:
#
#   - AC-04: a stopped container, a named volume and a tagged image without labels, the image an
#     unlabelled rebuild left dangling, and the image a pin's labelled rebuild replaced that a
#     container still uses, remain; an anonymous volume no container uses and the image a pin's
#     labelled rebuild replaced that no container uses go; the build cache's prune runs
#     with its bound (the stand-in's docker.io has no BuildKit CLI, so it has no build cache: the
#     host's first preflight proves the bound, 0049's plan, Verification);
#   - AC-06: a volume kept for a path that is gone goes, one kept for a path that exists remains;
#   - RQ-03: a container of a run whose time to live passed goes, one of a run that held the lock the
#     reaper's run now holds goes, one of the reaper's own run and one of a recent run without the lock
#     remain;
#   - RQ-09: one line per class.
#
#   bash tests/0049-docker-reap.stand-in.sh      (bash tests/run.sh --all runs it)
#
# covers: tests/lib/docker-preflight.sh tests/lib/stand-in-host.sh tests/stand-in-host/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/stand-in-host.sh

work=$(mktemp -d)
trap 'stand_in_down; rm -rf "$work"' EXIT

check "the stand-in starts" stand_in_up
check "alpine:3 is in the stand-in's Docker" stand_in_load_image alpine:3
check "the library is copied in" eval 'stand_in_exec -i sh -c "cat > /root/docker-preflight.sh" < tests/lib/docker-preflight.sh'

# What the reaper meets: built and created in the stand-in, the pinned image's three builds' ids kept
SETUP='set -e
cd /root
pin() { printf "FROM alpine:3\nLABEL c4-test.build=%s\n" "$1" \
    | docker build -q --label c4-infra.owner=c4-test -t c4-test/pinned:current - > /dev/null
  docker image inspect -f "{{.Id}}" c4-test/pinned:current > "/root/pinned-$1"; }
other() { printf "FROM alpine:3\nLABEL c4-test.build=%s\n" "$1" | docker build -q -t unlabelled/built:1 - > /dev/null
  docker image inspect -f "{{.Id}}" unlabelled/built:1 > "/root/other-$1"; }
docker create --name unlabelled-stopped alpine:3 true > /dev/null
docker volume create unlabelled-named > /dev/null
docker tag alpine:3 unlabelled/tagged:1
other 1
other 2
pin 1
docker create --name pinned-user c4-test/pinned:current true > /dev/null
pin 2
pin 3
docker run --name anonymous-user -v /data alpine:3 true > /dev/null
docker rm anonymous-user > /dev/null
docker volume ls -q -f dangling=true -f label=com.docker.volume.anonymous > /root/anonymous
docker volume create --label c4-infra.owner=c4-infra --label c4-infra.keep=/nonexistent-0049 kept-gone > /dev/null
docker volume create --label c4-infra.owner=c4-infra --label c4-infra.keep=/root kept-here > /dev/null
now=$(date +%s)
docker create --label c4-infra.run=old --label c4-infra.created=1000 --label c4-infra.ttl=60 --name run-expired alpine:3 true > /dev/null
docker create --label c4-infra.run=other --label c4-infra.created=$now --label c4-infra.ttl=14400 --label c4-infra.lock=the-lock --name run-lock-taken alpine:3 true > /dev/null
docker create --label c4-infra.run=mine --label c4-infra.created=$now --label c4-infra.ttl=14400 --label c4-infra.lock=the-lock --name run-mine alpine:3 true > /dev/null
docker create --label c4-infra.run=recent --label c4-infra.created=$now --label c4-infra.ttl=14400 --name run-recent alpine:3 true > /dev/null
echo c4-test/pinned:current > /root/pins'
check "what the reaper meets is set up" stand_in_exec bash -c "$SETUP"
check "an anonymous volume no container uses is there" eval '[ -n "$(stand_in_exec cat /root/anonymous | tr -d "\r")" ]'

stand_in_exec bash -c 'source /root/docker-preflight.sh && C4_INFRA_RUN=mine C4_DOCKER_LOCK=the-lock docker_reap --pins /root/pins' \
  > "$work/reap.log" 2>&1
status=$?
sed 's/^/# /' "$work/reap.log"
check "the reaper exits 0" test "$status" -eq 0

there() { # <container|volume|image> <name or id>
  stand_in_exec docker "$1" inspect "$2" > /dev/null 2>&1
}
pinned() { # <build>: its image id
  stand_in_exec cat "/root/pinned-$1" | tr -d '\r'
}
check "AC-04: the stopped container without labels remains" there container unlabelled-stopped
check "AC-04: the named volume without labels remains" there volume unlabelled-named
check "AC-04: the tagged image without labels remains" there image unlabelled/tagged:1
check "AC-04: the image an unlabelled rebuild left dangling remains (another project's)" \
  there image "$(stand_in_exec cat /root/other-1 | tr -d '\r')"
check "AC-04: the image a rebuild replaced, which a container uses, remains" there image "$(pinned 1)"
check "AC-04: the image a rebuild replaced, which no container uses, is gone" eval '! there image "$(pinned 2)"'
check "AC-04: the pin's current image remains" there image c4-test/pinned:current
check "AC-04: the anonymous volume no container uses is gone" \
  eval '! there volume "$(stand_in_exec cat /root/anonymous | tr -d "\r")"'
check "AC-04: the build cache's prune ran with its bound" grep -qE '^docker preflight: build cache: .* reclaimed \(bound 5 GB\)$' "$work/reap.log"
check "AC-06: the volume kept for a path that is gone is gone" eval '! there volume kept-gone'
check "AC-06: the volume kept for a path that exists remains" there volume kept-here
check "RQ-03: the container of a run whose time to live passed is gone" eval '! there container run-expired'
check "RQ-03: the container of a run that held the lock now held is gone" eval '! there container run-lock-taken'
check "RQ-03: the container of the reaper's own run remains" there container run-mine
check "RQ-03: the container of a recent run without the lock remains" there container run-recent
check "RQ-09: the reaper says what it removed, one line per class" \
  eval 'grep -qxF "docker preflight: runs over: 2 container(s), 0 network(s), 0 volume(s), 0 image(s) removed" "$work/reap.log" \
    && grep -qxF "docker preflight: kept, their path gone: 1 volume(s), 0 image(s) removed" "$work/reap.log" \
    && grep -qE "^docker preflight: anonymous volumes no container uses: 1 removed" "$work/reap.log" \
    && grep -qE "^docker preflight: images a pin replaced: 1 removed" "$work/reap.log"'
finish
