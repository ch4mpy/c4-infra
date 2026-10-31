#!/usr/bin/env bash
# 0050: tests/lib/docker-preflight.sh gives the same verdicts and prints the same numbers whatever the
# caller's locale, under C and under fr_FR.UTF-8 (a decimal comma), with an awk that honours the
# numeric locale: the system's awk when it does (mawk), else gawk --use-lc-numeric (Git Bash's gawk
# ignores it by default). No Docker: a docker shim prints the VM's measures (115.34 GB free, 2.4 GiB
# available) and logs its arguments.
#
#   - AC-01: floors 20 and 3, the VM's memory short and its disk not; floors 20 and 2, nothing short;
#   - AC-02: no number of the preflight's lines is written with a comma; the disk's says 115.3;
#   - AC-03: docker's sizes 1.5GB and 512.3MB sum to 2012300000 bytes;
#   - AC-04: a floor or the build cache's bound written 2,5 is 2.5; 2,5,1 and abc are not numbers;
#   - AC-05: under fr_FR.UTF-8, the shell that sourced the library still writes 1,5 (bash's printf).
#
#   bash tests/0050-preflight-locale.sh
#
# covers: tests/lib/docker-preflight.sh
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

FRENCH=fr_FR.UTF-8
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/shims" "$work/disk"
unset C4_INFRA_RUN C4_DOCKER_LOCK C4_DOCKER_PREFLIGHT C4_DOCKER_MIN_VM_DISK_GB C4_DOCKER_MIN_VM_MEMORY_GIB \
  C4_DOCKER_BUILD_CACHE_GB C4_DOCKER_LABEL_NS C4_DOCKER_REAP
export C4_DOCKER_DISK_DIR=$work/disk C4_DOCKER_MIN_HOST_DISK_GB=0 C4_DOCKER_MIN_HOST_MEMORY_GIB=0
export DOCKER_SHIM_LOG=$work/docker.log

cat > "$work/shims/docker" << 'EOF'
#!/usr/bin/env bash
echo "$*" >> "$DOCKER_SHIM_LOG"
case "$*" in
  *"df -Pk /"*)
    printf '%s\n' 'Filesystem 1024-blocks Used Available Capacity Mounted on' \
      'overlay 200000000 87363281 112636719 44% /' 'MemTotal: 8388608 kB' 'MemAvailable: 2516582 kB' ;;
  "builder prune --help") echo '      --max-used-space bytes   Maximum amount of disk space allowed to keep for cache' ;;
esac
EOF
chmod +x "$work/shims/docker"

locale_awk() { # the awk that honours the numeric locale: installs a shim when the system's doesn't
  if [ "$(LC_ALL=$FRENCH awk 'BEGIN { printf "%.1f", 1.5 }')" = 1,5 ]; then
    echo "awk ($(awk -W version 2>&1 | head -n 1))"
  elif command -v gawk > /dev/null; then
    printf '#!/usr/bin/env bash\nexec %q --use-lc-numeric "$@"\n' "$(command -v gawk)" > "$work/shims/awk"
    chmod +x "$work/shims/awk"
    echo "gawk --use-lc-numeric"
  fi
}

with_library() { # <locale> <commands>: their output, in a bash under that locale that sourced the library
  LC_ALL=$1 PATH="$work/shims:$PATH" bash -c "source tests/lib/docker-preflight.sh; $2" 2>&1
}

check "the locale $FRENCH is installed" eval 'locale -a | grep -qiE "^fr_FR[.]utf-?8$"'
awk_used=$(locale_awk)
check "an awk honours the numeric locale (mawk, or gawk --use-lc-numeric): ${awk_used:-none}" test -n "$awk_used"
check "under $FRENCH, that awk writes a decimal comma" \
  eval '[ "$(LC_ALL=$FRENCH PATH="$work/shims:$PATH" awk "BEGIN { printf \"%.1f\", 1.5 }")" = 1,5 ]'

for loc in C "$FRENCH"; do
  short=$(with_library "$loc" 'C4_DOCKER_MIN_VM_DISK_GB=20 C4_DOCKER_MIN_VM_MEMORY_GIB=3 docker_preflight --no-clean; echo "exit $?"')
  room=$(with_library "$loc" 'C4_DOCKER_MIN_VM_DISK_GB=20 C4_DOCKER_MIN_VM_MEMORY_GIB=2 docker_preflight --no-clean; echo "exit $?"')
  check "AC-01 ($loc): floors 20 and 3, exit 1" grep -qx 'exit 1' <<< "$short"
  check "AC-01 ($loc): the VM's memory named short" grep -q "^docker preflight: short: Docker's VM has 2.4 GiB" <<< "$short"
  check "AC-01 ($loc): the VM's disk not short" eval '! grep -q "^docker preflight: short: Docker.s disk" <<< "$short"'
  check "AC-01 ($loc): floors 20 and 2, exit 0" grep -qx 'exit 0' <<< "$room"
  check "AC-02 ($loc): the disk's line says 115.3" \
    grep -qxF 'docker preflight: VM disk: 115.3 GB free (floor 20)' <<< "$short"
  check "AC-02 ($loc): no number written with a comma" \
    eval '! grep "^docker preflight:" <<< "$short$room" | grep -E "[0-9],[0-9]"'
  check "AC-03 ($loc): 1.5GB and 512.3MB are 2012300000 bytes" \
    eval '[ "$(with_library "$loc" "_docker_bytes 1.5GB 512.3MB")" = 2012300000 ]'
  check "AC-04 ($loc): a floor written 2,5 is 2.5" grep -qxF 'docker preflight: VM disk: 115.3 GB free (floor 2.5)' \
    <<< "$(with_library "$loc" 'C4_DOCKER_MIN_VM_DISK_GB=2,5 C4_DOCKER_MIN_VM_MEMORY_GIB=0 docker_preflight --no-clean')"
  for value in 2,5,1 abc; do
    refused=$(with_library "$loc" "C4_DOCKER_MIN_VM_DISK_GB=$value docker_preflight --no-clean; echo \"exit \$?\"")
    check "AC-04 ($loc): a floor written $value is not a number" \
      grep -qxF "docker preflight: C4_DOCKER_MIN_VM_DISK_GB is '$value', not a number" <<< "$refused"
    check "AC-04 ($loc): and stops the run" grep -qx 'exit 1' <<< "$refused"
  done
  : > "$DOCKER_SHIM_LOG"
  with_library "$loc" 'C4_DOCKER_BUILD_CACHE_GB=2,5 _docker_reap_unlabelled' > /dev/null
  check "AC-04 ($loc): a bound written 2,5 keeps 2500000000 bytes of build cache" \
    grep -qx 'builder prune -f --max-used-space 2500000000' "$DOCKER_SHIM_LOG"
done

check "AC-05: the shell that sourced the library keeps its locale" eval \
  '[ "$(with_library "$FRENCH" "docker_preflight --no-clean > /dev/null; printf \"%.1f\n\" 1,5" | tail -n 1)" = 1,5 ]'

finish
