#!/usr/bin/env bash
# 0049: tests/lib/docker-preflight.sh's reaper on what it may and may not remove, inside a stand-in's
# own Docker (containerd's image store, as Docker Desktop's), never the host's: the library copied in
# and run there by bash as the lock's holder (C4_INFRA_RUN=mine, C4_DOCKER_LOCK=the-lock), with a pins
# file naming c4-test/pinned and one of its digests:
#
#   - AC-04, IV-01: a stopped container, a named volume and a tagged image without labels, the image an
#     unlabelled rebuild left dangling, the dangling images of a labelled rebuild that a stopped
#     container and a running one use, a pinned repository's untagged digest reference a container was
#     created from, one the pins file names, and an unpinned repository's untagged digest reference,
#     remain; an anonymous volume no container uses, the dangling image of a labelled rebuild no
#     container uses, and a pinned repository's untagged digest reference nothing uses, go (the digest
#     references made as a pull makes them: names of containerd's moby namespace, through dockerd's own
#     containerd); the build cache's prune runs with its bound (the stand-in's docker.io has no BuildKit
#     CLI, so it has no build cache: the host's first preflight proves the bound, 0049's plan,
#     Verification);
#   - AC-06: a volume kept for a path that is gone goes, one kept for a path that exists remains;
#   - RQ-03: a container of a run whose time to live passed goes, one of a run that held the lock the
#     reaper's run now holds goes, one of the reaper's own run and one of a recent run without the lock
#     remain;
#   - RQ-09: one line per class; the replaced images counted at least as the three above (the
#     stand-in's volume keeps its images between runs, an earlier run's dangling builds with them).
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

# What the reaper meets, built and created in the stand-in (an earlier run's images, labelled
# c4-test.build, removed first: the stand-in's volume keeps them); the ids and digests it is checked by in /root
SETUP='set -e
cd /root
docker images -q --no-trunc --filter label=c4-test.build | sort -u | xargs -r docker rmi -f > /dev/null 2>&1 || true
build() { # <repository:tag> <build> [docker build option…]: its id in /root/<build>
  local ref=$1 name=$2
  shift 2
  printf "FROM alpine:3\nLABEL c4-test.build=%s\n" "$name" | docker build -q "$@" -t "$ref" - > /dev/null 2>&1
  docker image inspect -f "{{.Id}}" "$ref" > "/root/$name"
}
ctr_moby() { ctr --address /run/docker/containerd/containerd.sock -n moby "$@" 2> /dev/null; }
digest_ref() { # <repository:tag> <build>: a name <repository>@<digest> for what the tag names, as a pull leaves it
  local digest
  digest=$(ctr_moby images ls | awk -v n="docker.io/$1" '\''$1 == n { print $3 }'\'')
  ctr_moby images tag "docker.io/$1" "docker.io/${1%:*}@$digest" > /dev/null
  echo "$digest" > "/root/$2-digest"
}
docker create --name unlabelled-stopped alpine:3 true > /dev/null
docker volume create unlabelled-named > /dev/null
docker tag alpine:3 unlabelled/tagged:1
build unlabelled/built:1 other-1
build unlabelled/built:1 other-2
build c4-test/labelled:1 labelled-1 --label c4-infra.owner=c4-test
docker create --name labelled-stopped c4-test/labelled:1 true > /dev/null
build c4-test/labelled:1 labelled-2 --label c4-infra.owner=c4-test
docker run -d --name labelled-running c4-test/labelled:1 sleep 600 > /dev/null
build c4-test/labelled:1 labelled-3 --label c4-infra.owner=c4-test
build c4-test/labelled:1 labelled-4 --label c4-infra.owner=c4-test
build c4-test/labelled:1 labelled-5 --label com.docker.compose.project=c4-infra
docker run -d --name stack-running c4-test/labelled:1 sleep 600 > /dev/null
build c4-test/labelled:1 labelled-6 --label com.docker.compose.project=c4-infra
build c4-test/pinned:current pinned-gone
digest_ref c4-test/pinned:current pinned-gone
build c4-test/pinned:current pinned-used
digest_ref c4-test/pinned:current pinned-used
docker create --name pinned-by-digest "c4-test/pinned@$(cat /root/pinned-used-digest)" true > /dev/null
build c4-test/pinned:current pinned-named
digest_ref c4-test/pinned:current pinned-named
build c4-test/pinned:current pinned-current
build c4-test/shared:1 shared-old
digest_ref c4-test/shared:1 shared-old
build c4-test/shared:1 shared-current
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
printf "%s\n" c4-test/pinned:current "c4-test/pinned@$(cat /root/pinned-named-digest)" > /root/pins'
check "what the reaper meets is set up" stand_in_exec bash -c "$SETUP"
check "an anonymous volume no container uses is there" eval '[ -n "$(stand_in_exec cat /root/anonymous | tr -d "\r")" ]'
check "the pinned repository's three old builds are untagged digest references" \
  eval '[ "$(stand_in_exec docker images --digests --format "{{.Tag}}" c4-test/pinned | tr -d "\r" | grep -cx "<none>")" = 3 ]'

stand_in_exec bash -c 'source /root/docker-preflight.sh && C4_INFRA_RUN=mine C4_DOCKER_LOCK=the-lock docker_reap --pins /root/pins' \
  > "$work/reap.log" 2>&1
status=$?
sed 's/^/# /' "$work/reap.log"
check "the reaper exits 0" test "$status" -eq 0

there() { # <container|volume|image> <name or id>
  stand_in_exec docker "$1" inspect "$2" > /dev/null 2>&1
}
saved() { # <name>: what the setup saved in /root/<name>
  stand_in_exec cat "/root/$1" | tr -d '\r'
}
check "AC-04: the stopped container without labels remains" there container unlabelled-stopped
check "AC-04: the named volume without labels remains" there volume unlabelled-named
check "AC-04: the tagged image without labels remains" there image unlabelled/tagged:1
check "AC-04: the image an unlabelled rebuild left dangling remains (another project's)" there image "$(saved other-1)"
check "AC-04, IV-01: a labelled rebuild's dangling image a stopped container uses remains" there image "$(saved labelled-1)"
check "AC-04, IV-01: a labelled rebuild's dangling image a running container uses remains" there image "$(saved labelled-2)"
check "AC-04, IV-01: the stack's rebuild's dangling image a running container uses remains" there image "$(saved labelled-5)"
check "AC-04: a labelled rebuild's dangling image no container uses is gone" eval '! there image "$(saved labelled-3)"'
check "AC-04: the labelled builds' current image remains" there image c4-test/labelled:1
check "AC-04: a pinned repository's untagged digest reference nothing uses is gone" \
  eval '! there image "c4-test/pinned@$(saved pinned-gone-digest)"'
check "AC-04, IV-01: one a container was created from remains" there image "c4-test/pinned@$(saved pinned-used-digest)"
check "AC-04: one the pins file names remains" there image "c4-test/pinned@$(saved pinned-named-digest)"
check "AC-04: the pin's current image remains" there image c4-test/pinned:current
check "AC-04, IV-01: an unpinned repository's untagged digest reference remains" \
  there image "c4-test/shared@$(saved shared-old-digest)"
check "AC-04: the running containers still run" \
  eval '[ "$(stand_in_exec docker inspect -f "{{.State.Status}}" labelled-running stack-running | tr -d "\r" | sort -u)" = running ]'
check "AC-04: the anonymous volume no container uses is gone" eval '! there volume "$(saved anonymous)"'
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
    && grep -qE "^docker preflight: images a pin replaced: ([3-9]|[1-9][0-9]+) removed" "$work/reap.log"'
finish
