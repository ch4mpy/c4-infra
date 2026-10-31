# Docker's housekeeping for the suite and its neighbours (intent 0049, the twin of the skills' 0122):
# the labels of what a run creates, a reaper of what runs over left behind, and a preflight that cleans,
# then checks that Docker has the disk and memory a run needs, before its first test. Source it; it
# sources nothing and needs bash, coreutils, awk, sed and the docker CLI, so that the skills read it with
# `git show main:tests/lib/docker-preflight.sh` and the generated projects through C4_INFRA_DIR.
#
#   docker_labels <owner> [ttl]   the `--label` arguments of a run's resource, one per line (ttl in
#                                 seconds, 14400 by default): <ns>.owner, <ns>.run ($C4_INFRA_RUN),
#                                 <ns>.created (epoch seconds), <ns>.ttl, and <ns>.lock ($C4_DOCKER_LOCK)
#                                 when the run holds a lock; e.g.
#                                 mapfile -t C4_LABELS < <(docker_labels c4-infra)
#                                 docker run "${C4_LABELS[@]}" …
#   docker_keep_labels <owner> <path>
#                                 those of a resource kept between runs (<ns>.owner, <ns>.keep): an
#                                 orphan once <path> no longer exists; under Git Bash a path is written
#                                 in its drive's form (cygpath -m: D:/…), whoever gives it
#   docker_reap [--pins <file>]   removes the labelled resources of the runs over and the kept ones
#                                 whose path is gone; then, unless C4_DOCKER_REAP=labelled, the build
#                                 cache beyond its bound, the anonymous volumes no container uses, and
#                                 the images a pull or a rebuild replaced: the untagged references of
#                                 the repositories <file> names (one image reference per line) that no
#                                 pin's digest names, and the dangling images the stack's builds
#                                 (com.docker.compose.project=c4-infra) or a labelled build
#                                 (<ns>.owner) left; one `docker preflight:` line per class. A pins file
#                                 names only repositories its caller builds: a shared repository's
#                                 digest references (postgres@sha256:…) may be another project's
#   docker_preflight [--no-clean] [--pins <file>]
#                                 docker_reap (not with --no-clean), then Docker's free disk and
#                                 available memory, in its VM and on the host, each against its floor:
#                                 0, or 1 with a line naming what is short and what a human can do
#
# A run is over when its time to live has passed, or when the lock it held ($C4_DOCKER_LOCK) is now
# another run's: only the lock's holder reaps, before its first test, so that no cleaning overlaps a
# test. The suite's lock and its queue's tickets carry no run label (tests/lib/suite-lock.sh). No image
# a container uses, running or stopped, by its id, a digest or a tag, is ever removed, whatever the
# daemon would allow. A kept path written by another system (a Windows drive's seen from Linux, or the
# reverse) is never taken for gone. Nothing here stops, restarts or resets Docker, nor compacts its
# disk image: a human does.
#
# Environment: C4_INFRA_RUN (set and exported when this file is sourced and it is unset, so that a
# command substitution sees the same run), C4_DOCKER_LABEL_NS (c4-infra; a test's own namespace),
# C4_DOCKER_LOCK, C4_DOCKER_REAP=labelled, C4_DOCKER_PREFLIGHT=off (docker_preflight does nothing), the
# floors C4_DOCKER_MIN_VM_DISK_GB (20), C4_DOCKER_MIN_HOST_DISK_GB (20), C4_DOCKER_MIN_VM_MEMORY_GIB (3)
# and C4_DOCKER_MIN_HOST_MEMORY_GIB (6, memory and swap), the build cache's bound C4_DOCKER_BUILD_CACHE_GB
# (5), and C4_DOCKER_DISK_DIR, the host's directory of Docker's disk image (by default Docker Desktop's:
# ~/.docker/desktop/vms/0/data on Linux, %LOCALAPPDATA%\Docker\wsl\disk on Windows). A floor or the bound
# may be written with a decimal point or a comma (2.5, 2,5). The numbers this file reads and prints, and
# its verdicts, don't depend on the caller's locale (intent 0050), which it leaves as it is.

if [ -z "${C4_INFRA_RUN:-}" ]; then
  C4_INFRA_RUN=$(date +%s)-$$-$RANDOM$RANDOM
fi
export C4_INFRA_RUN

docker_labels() { # <owner> [ttl]
  local ns=${C4_DOCKER_LABEL_NS:-c4-infra}
  printf -- '--label\n%s\n' "$ns.owner=$1" "$ns.run=$C4_INFRA_RUN" "$ns.created=$(date +%s)" "$ns.ttl=${2:-14400}"
  [ -z "${C4_DOCKER_LOCK:-}" ] || printf -- '--label\n%s\n' "$ns.lock=$C4_DOCKER_LOCK"
}

docker_keep_labels() { # <owner> <path>
  local ns=${C4_DOCKER_LABEL_NS:-c4-infra} path=$2
  if [[ $path == /* ]] && command -v cygpath > /dev/null 2>&1; then
    path=$(cygpath -m "$path")
  fi
  printf -- '--label\n%s\n' "$ns.owner=$1" "$ns.keep=$path"
}

_docker_over() { # <run> <created> <ttl> <lock> <now>: the run is over
  [ "$1" != "$C4_INFRA_RUN" ] || return 1
  if [[ $2 =~ ^[0-9]+$ && $3 =~ ^[0-9]+$ ]] && [ $(($2 + $3)) -lt "$5" ]; then
    return 0
  fi
  [ -n "$4" ] && [ "$4" = "${C4_DOCKER_LOCK:-}" ]
}

_docker_gone() { # <path>: in this system's form, and no longer there
  if command -v cygpath > /dev/null 2>&1; then
    [[ $1 =~ ^[A-Za-z]:/ ]] || return 1
  else
    [[ $1 == /* ]] || return 1
  fi
  [ ! -e "$1" ]
}

_docker_unused() { # <volume|ancestor> <name or id>: no container, running or stopped, uses it
  [ -z "$(docker ps -aq --filter "$1=$2" 2> /dev/null | tr -d '\r')" ]
}

_docker_ref() { # <image reference>: as Docker names it, docker.io's prefixes off, :latest when untagged
  local ref=${1#docker.io/}
  ref=${ref#library/}
  [[ $ref == *@* || ${ref##*/} == *:* || $ref =~ ^(sha256:)?[0-9a-f]{12,64}$ ]] || ref=$ref:latest
  printf '%s\n' "$ref"
}

_docker_used=
_docker_used_refresh() { # what the containers, running or stopped, were created from: image ids and references
  local ids
  ids=$(docker ps -aq --no-trunc 2> /dev/null | tr -d '\r')
  # shellcheck disable=SC2086 # one id per word: container ids hold no blank
  _docker_used=$([ -z "$ids" ] || docker inspect -f '{{.Image}} {{.Config.Image}}' $ids 2> /dev/null | tr -d '\r' \
    | while read -r id ref; do
      printf '%s\n' "$id"
      _docker_ref "$ref"
    done)
}

_docker_in_use() { # <image>: a container uses it by its id, a digest or a tag; an image that can't be read counts as used
  local id names used
  id=$(docker image inspect -f '{{.Id}}' "$1" 2> /dev/null | tr -d '\r')
  [ -n "$id" ] || return 0
  names=$(docker image inspect -f '{{range .RepoTags}}{{println .}}{{end}}{{range .RepoDigests}}{{println .}}{{end}}' "$1" 2> /dev/null \
    | tr -d '\r' | while read -r ref; do [ -z "$ref" ] || _docker_ref "$ref"; done)
  while IFS= read -r used; do
    [ -n "$used" ] || continue
    [ "$used" = "$id" ] && return 0
    [[ $used =~ ^(sha256:)?[0-9a-f]{12,64}$ && $id == sha256:${used#sha256:}* ]] && return 0
    grep -qxF -- "$used" <<< "$names" && return 0
  done <<< "$_docker_used"
  return 1
}

_docker_awk() { # <awk arguments>…: awk reading and writing numbers with a decimal point, whatever the caller's locale
  LC_ALL=C awk "$@"
}

_docker_bytes() { # <size as docker prints it>…: their sum in bytes
  printf '%s\n' "$@" | _docker_awk '{ n = $0; unit = $0; sub(/[A-Za-z]+$/, "", n); sub(/^[0-9.]+/, "", unit)
      m = 1; if (unit == "kB" || unit == "KB") m = 1e3; else if (unit == "MB") m = 1e6
      else if (unit == "GB") m = 1e9; else if (unit == "TB") m = 1e12
      total += n * m } END { printf "%.0f\n", total }'
}

_docker_size() { # <bytes>: in GB, or in MB below 1 GB, one decimal
  _docker_awk -v b="$1" 'BEGIN { if (b < 1e9) printf "%.1f MB\n", b / 1e6; else printf "%.1f GB\n", b / 1e9 }'
}

docker_reap() { # [--pins <file>]
  local ns=${C4_DOCKER_LABEL_NS:-c4-infra} pins_file= now id run created ttl lock ref keep
  local -a pins=()
  local containers=0 volumes=0 networks=0 images=0 kept_volumes=0 kept_images=0
  while [ $# -gt 0 ]; do
    case $1 in
      --pins)
        pins_file=$2
        shift 2
        ;;
      *)
        echo "docker_reap: unknown option $1" >&2
        return 2
        ;;
    esac
  done
  if [ -n "$pins_file" ]; then
    mapfile -t pins < <(tr -d '\r' < "$pins_file" | sed 's/#.*//; s/[[:space:]]//g; /^$/d')
  fi
  now=$(date +%s)
  local fields="{{.Label \"$ns.run\"}}|{{.Label \"$ns.created\"}}|{{.Label \"$ns.ttl\"}}|{{.Label \"$ns.lock\"}}"
  docker info > /dev/null 2>&1 || { echo "docker preflight: docker doesn't answer"; return 1; }

  while IFS='|' read -r id run created ttl lock; do
    [ -n "$id" ] && _docker_over "$run" "$created" "$ttl" "$lock" "$now" || continue
    docker rm -f -v "$id" > /dev/null 2>&1 && containers=$((containers + 1))
  done < <(docker ps -a --filter "label=$ns.run" --format "{{.ID}}|$fields" | tr -d '\r')
  while IFS='|' read -r id run created ttl lock; do
    [ -n "$id" ] && _docker_over "$run" "$created" "$ttl" "$lock" "$now" || continue
    docker network rm "$id" > /dev/null 2>&1 && networks=$((networks + 1))
  done < <(docker network ls --filter "label=$ns.run" --format "{{.ID}}|$fields" | tr -d '\r')
  while IFS='|' read -r id run created ttl lock; do
    [ -n "$id" ] && _docker_over "$run" "$created" "$ttl" "$lock" "$now" || continue
    docker volume rm "$id" > /dev/null 2>&1 && volumes=$((volumes + 1))
  done < <(docker volume ls --filter "label=$ns.run" --format "{{.Name}}|$fields" | tr -d '\r')
  _docker_used_refresh
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    IFS='|' read -r run created ttl lock < <(docker image inspect -f \
      "{{index .Config.Labels \"$ns.run\"}}|{{index .Config.Labels \"$ns.created\"}}|{{index .Config.Labels \"$ns.ttl\"}}|{{index .Config.Labels \"$ns.lock\"}}" \
      "$ref" 2> /dev/null | tr -d '\r')
    _docker_over "$run" "$created" "$ttl" "$lock" "$now" && ! _docker_in_use "$ref" || continue
    docker rmi "$ref" > /dev/null 2>&1 && images=$((images + 1))
  done < <(docker images --filter "label=$ns.run" --format '{{.Repository}}:{{.Tag}}' | tr -d '\r' | grep -v '<none>')
  echo "docker preflight: runs over: $containers container(s), $networks network(s), $volumes volume(s), $images image(s) removed"

  while IFS='|' read -r id keep; do
    [ -n "$id" ] && _docker_gone "$keep" && _docker_unused volume "$id" || continue
    docker volume rm "$id" > /dev/null 2>&1 && kept_volumes=$((kept_volumes + 1))
  done < <(docker volume ls --filter "label=$ns.keep" --format "{{.Name}}|{{.Label \"$ns.keep\"}}" | tr -d '\r')
  while IFS='|' read -r ref id; do
    [ -n "$ref" ] || continue
    keep=$(docker image inspect -f "{{index .Config.Labels \"$ns.keep\"}}" "$ref" 2> /dev/null | tr -d '\r')
    _docker_gone "$keep" && ! _docker_in_use "$ref" || continue
    docker rmi "$ref" > /dev/null 2>&1 && kept_images=$((kept_images + 1))
  done < <(docker images --filter "label=$ns.keep" --format '{{.Repository}}:{{.Tag}}|{{.ID}}' | tr -d '\r' | grep -v '<none>')
  echo "docker preflight: kept, their path gone: $kept_volumes volume(s), $kept_images image(s) removed"

  [ "${C4_DOCKER_REAP:-}" != labelled ] || return 0
  _docker_reap_unlabelled "${pins[@]}"
}

_docker_reap_unlabelled() { # <pinned image reference>…
  local bound=${C4_DOCKER_BUILD_CACHE_GB:-5} option out total ref repo digest tag id size removed=0
  local -a sizes=() digests=() repos=()
  if ! [[ $bound =~ ^[0-9]+([.,][0-9]+)?$ ]]; then
    echo "docker preflight: C4_DOCKER_BUILD_CACHE_GB is '$bound', not a number of GB"
    return 1
  fi
  bound=${bound/,/.}
  option=--max-used-space
  docker builder prune --help 2>&1 | grep -q -- --max-used-space || option=--keep-storage
  out=$(docker builder prune -f "$option" "$(_docker_awk -v g="$bound" 'BEGIN { printf "%.0f", g * 1e9 }')" 2>&1 | tr -d '\r')
  total=$(sed -n 's/^Total[^:]*:[[:space:]]*//p' <<< "$out" | tail -n 1)
  echo "docker preflight: build cache: ${total:-0B} reclaimed (bound $bound GB)"

  out=$(docker volume prune -f --filter label=com.docker.volume.anonymous 2>&1 | tr -d '\r')
  total=$(sed -n 's/^Total reclaimed space:[[:space:]]*//p' <<< "$out")
  removed=$(_docker_awk '/^Deleted Volumes:/ { on = 1; next } on && NF == 0 { on = 0 } on { n++ } END { print n + 0 }' <<< "$out")
  echo "docker preflight: anonymous volumes no container uses: $removed removed (${total:-0B})"

  for ref in "$@"; do
    digest=
    if [[ $ref == *@* ]]; then
      digest=${ref#*@}
      ref=${ref%%@*}
    fi
    tag=${ref##*/}
    [[ $tag == *:* ]] && ref=${ref%:*}
    repos+=("$ref")
    [ -z "$digest" ] || digests+=("$digest")
  done
  removed=0
  for repo in $(printf '%s\n' "${repos[@]}" | LC_ALL=C sort -u); do
    while IFS='|' read -r tag digest id size; do
      [ "$tag" = '<none>' ] || continue
      [[ " ${digests[*]} " == *" $digest "* ]] && continue
      if [ "$digest" != '<none>' ]; then ref=$repo@$digest; else ref=$id; fi
      ! _docker_in_use "$ref" && ! _docker_in_use "$id" || continue
      docker rmi "$ref" > /dev/null 2>&1 || continue
      removed=$((removed + 1))
      sizes+=("$size")
    done < <(docker images --digests --no-trunc --format '{{.Tag}}|{{.Digest}}|{{.ID}}|{{.Size}}' "$repo" 2> /dev/null | tr -d '\r')
  done
  # A rebuild leaves its predecessor dangling, no repository left to name it: the stack's builds and
  # the labelled ones are known by their labels
  while IFS='|' read -r id size; do
    [ -n "$id" ] && ! _docker_in_use "$id" || continue
    docker rmi "$id" > /dev/null 2>&1 || continue
    removed=$((removed + 1))
    sizes+=("$size")
  done < <({ docker images -f dangling=true -f label=com.docker.compose.project=c4-infra --no-trunc --format '{{.ID}}|{{.Size}}'
    docker images -f dangling=true -f "label=${C4_DOCKER_LABEL_NS:-c4-infra}.owner" --no-trunc --format '{{.ID}}|{{.Size}}'; } \
    2> /dev/null | tr -d '\r' | LC_ALL=C sort -u)
  echo "docker preflight: images a pin replaced: $removed removed ($(_docker_size "$(_docker_bytes "${sizes[@]}")"))"
}

_docker_disk_dir() { # the host's directory of Docker's disk image, or nothing
  local dir
  if [ -n "${C4_DOCKER_DISK_DIR:-}" ]; then
    dir=$C4_DOCKER_DISK_DIR
  elif command -v cygpath > /dev/null 2>&1 && [ -n "${LOCALAPPDATA:-}" ]; then
    dir="$(cygpath -u "$LOCALAPPDATA")/Docker/wsl/disk"
  else
    dir=$HOME/.docker/desktop/vms/0/data
  fi
  [ ! -d "$dir" ] || printf '%s' "$dir"
}

_docker_floor() { # <variable> <default>: its value, a decimal comma made a point, or nothing and a line when it isn't a number
  local value=${!1:-$2}
  if [[ $value =~ ^[0-9]+([.,][0-9]+)?$ ]]; then
    printf '%s' "${value/,/.}"
  else
    echo "docker preflight: $1 is '$value', not a number" >&2
  fi
}

_docker_short() { # <measure> <floor>: the measure is below the floor
  _docker_awk -v m="$1" -v f="$2" 'BEGIN { exit !(m < f) }'
}

docker_preflight() { # [--no-clean] [--pins <file>]
  local clean=true out err vm_disk vm_memory dir host_disk where host_memory field swap short=0 compact
  local vm_disk_floor host_disk_floor vm_memory_floor host_memory_floor
  local -a reap=() C4_LABELS=()
  while [ $# -gt 0 ]; do
    case $1 in
      --no-clean)
        clean=false
        shift
        ;;
      --pins)
        reap=(--pins "$2")
        shift 2
        ;;
      *)
        echo "docker_preflight: unknown option $1" >&2
        return 2
        ;;
    esac
  done
  if [ "${C4_DOCKER_PREFLIGHT:-}" = off ]; then
    echo "docker preflight: off (C4_DOCKER_PREFLIGHT=off)"
    return 0
  fi
  vm_disk_floor=$(_docker_floor C4_DOCKER_MIN_VM_DISK_GB 20) && [ -n "$vm_disk_floor" ] || return 1
  host_disk_floor=$(_docker_floor C4_DOCKER_MIN_HOST_DISK_GB 20) && [ -n "$host_disk_floor" ] || return 1
  vm_memory_floor=$(_docker_floor C4_DOCKER_MIN_VM_MEMORY_GIB 3) && [ -n "$vm_memory_floor" ] || return 1
  host_memory_floor=$(_docker_floor C4_DOCKER_MIN_HOST_MEMORY_GIB 6) && [ -n "$host_memory_floor" ] || return 1
  if $clean; then
    docker_reap "${reap[@]}" || return 1
  fi

  mapfile -t C4_LABELS < <(docker_labels c4-infra 300)
  err=$(mktemp)
  out=$(MSYS_NO_PATHCONV=1 docker run --rm "${C4_LABELS[@]}" alpine:3 sh -c 'df -Pk /; cat /proc/meminfo' 2> "$err" | tr -d '\r')
  vm_disk=$(_docker_awk '$NF == "/" && $4 ~ /^[0-9]+$/ { printf "%.1f", $4 * 1024 / 1e9; exit }' <<< "$out")
  vm_memory=$(_docker_awk '/^MemAvailable:/ { printf "%.1f", $2 / 1048576 }' <<< "$out")
  if [ -z "$vm_disk" ] || [ -z "$vm_memory" ]; then
    echo "docker preflight: Docker's VM can't be measured (docker run alpine:3):"
    { printf '%s\n' "$out"; tr -d '\r' < "$err"; } | tail -n 3 | sed 's/^/  /'
    rm -f "$err"
    return 1
  fi
  rm -f "$err"
  echo "docker preflight: VM disk: $vm_disk GB free (floor $vm_disk_floor)"
  if _docker_short "$vm_disk" "$vm_disk_floor"; then
    echo "docker preflight: short: Docker's disk has $vm_disk GB free, $vm_disk_floor needed after cleaning: \`docker system df -v\` shows what holds it; images, volumes and build cache no run labels are a human's to remove"
    short=1
  fi
  echo "docker preflight: VM memory: $vm_memory GiB available (floor $vm_memory_floor)"
  if _docker_short "$vm_memory" "$vm_memory_floor"; then
    echo "docker preflight: short: Docker's VM has $vm_memory GiB of memory available, $vm_memory_floor needed: stop the containers no one needs, or give Docker more memory (Docker Desktop: Settings, Resources)"
    short=1
  fi

  dir=$(_docker_disk_dir)
  if [ -n "$dir" ]; then
    host_disk=$(df -Pk "$dir" | _docker_awk 'NR == 2 { printf "%.1f", $4 * 1024 / 1e9 }')
    if command -v cygpath > /dev/null 2>&1; then
      where=$(df -Pk "$dir" | _docker_awk 'NR == 2 { print $1 }')
    else
      where=$(df -Pk "$dir" | _docker_awk 'NR == 2 { print $6 }')
    fi
    echo "docker preflight: host disk under Docker's disk image ($where): $host_disk GB free (floor $host_disk_floor)"
    if _docker_short "$host_disk" "$host_disk_floor"; then
      if command -v cygpath > /dev/null 2>&1; then
        compact="on Windows: quit Docker Desktop, run wsl --shutdown, then compact the image from an elevated PowerShell: Optimize-VHD -Path <its .vhdx> -Mode Full (Hyper-V's module), or diskpart: select vdisk file=<its .vhdx>, compact vdisk"
      else
        compact="on Linux: Docker Desktop's own procedure (its documentation, disk usage), Docker Desktop quit first"
      fi
      echo "docker preflight: short: the host's disk holding Docker's disk image ($where) has $host_disk GB free, $host_disk_floor needed after cleaning; the image, in $dir, allocates $(du -sk "$dir" | _docker_awk '{ printf "%.1f GB", $1 * 1024 / 1e9 }'). Giving its free blocks back to the host is a human's action, $compact"
      short=1
    fi
  else
    echo "docker preflight: host disk under Docker's disk image: not measured (no Docker Desktop disk image found; C4_DOCKER_DISK_DIR names its directory)"
  fi

  if grep -q '^MemAvailable:' /proc/meminfo 2> /dev/null; then field=MemAvailable; else field=MemFree; fi
  host_memory=$(_docker_awk -v f="$field:" '$1 == f { printf "%.1f", $2 / 1048576 }' /proc/meminfo 2> /dev/null)
  swap=$(_docker_awk '$1 == "SwapFree:" { printf "%.1f", $2 / 1048576 }' /proc/meminfo 2> /dev/null)
  if [ -n "$host_memory" ]; then
    echo "docker preflight: host memory: $host_memory GiB $field + ${swap:-0} GiB SwapFree (floor $host_memory_floor)"
    if _docker_short "$(_docker_awk -v a="$host_memory" -v b="${swap:-0}" 'BEGIN { print a + b }')" "$host_memory_floor"; then
      echo "docker preflight: short: the host has $host_memory GiB of memory ($field) and ${swap:-0} GiB of swap free, $host_memory_floor needed: close what no one needs, or give the host more swap"
      short=1
    fi
  else
    echo "docker preflight: host memory: not measured (no /proc/meminfo)"
  fi
  [ "$short" -eq 0 ] || echo "docker preflight: stopped before the first test (the floors: C4_DOCKER_MIN_*; C4_DOCKER_PREFLIGHT=off skips the preflight)"
  return "$short"
}
