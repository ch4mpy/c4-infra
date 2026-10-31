#!/usr/bin/env bash
# 0034: tests/0007-dev.sh's negative checks pass only on a failed connection from an existing
# c4-infra.faito; a missing network or image, or a docker command that fails, makes them KO, naming
# the cause. tests/0007-dev.sh runs four times, from this repository:
#
#   - without Faito's network: a copy where c4-infra.faito is c4-infra.0034-no-such-app (parts tickee
#     guard): a KO naming the network and register-app.sh --app faito, both negative checks and the
#     dev alias check KO naming it, no ok from it;
#   - without the probe image: a copy where alpine:3 is alpine:0034-no-such-tag (part tickee): the
#     control and both negative checks KO, naming the image;
#   - the stand-in on Faito's network too (a docker wrapper connects it once it starts; part tickee):
#     by name and at one of its addresses, KO "succeeded";
#   - docker failing (the wrapper fails `docker ps … name=^tickee.network-standin$` and `docker compose
#     config --format json`; parts tickee guard): the stand-in's removal and the dev alias check KO
#     naming the command; both negative checks still ok (the real isolation).
#
#   bash tests/0034-negative-checks.sh
#
# Needs what tests/0007-dev.sh needs: the dev stack (bash up.sh), Faito registered.
#
# covers: tests/0007-dev.sh
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

NO_NETWORK=c4-infra.0034-no-such-app
NO_IMAGE=alpine:0034-no-such-tag
STANDIN=tickee.network-standin
# the negative check by address, whichever address it names
BY_ADDRESS="[0-9.]+:7080 can't be reached\$"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

variant() { # <name> <text of tests/0007-dev.sh> <parts…>: its output in $work/<name>.log, its exit status in .status
  local name=$1 text=$2
  shift 2
  bash -c "$text" tests/0007-dev.sh "$@" > "$work/$name.log" 2>&1
  echo $? > "$work/$name.status"
  sed -i 's/\r$//' "$work/$name.log"
}
exited() { # <name> <status>
  [ "$(cat "$work/$1.status")" = "$2" ] || { echo "exit $(cat "$work/$1.status"); its log:"; tail -n 20 "$work/$1.log"; return 1; }
}
ko_naming() { # <name> <label regex> <cause fragment>: a KO line matching the label, the cause in the lines under it
  awk -v label="$2" -v cause="$3" '
    /^KO - / { inside = $0 ~ label; next }
    /^     / { if (inside && index($0, cause)) found = 1; next }
    { inside = 0 }
    END { exit !found }' "$work/$1.log" \
    || { echo "no KO matching '$2' naming '$3'; its log:"; grep -E '^(ok|KO) - ' "$work/$1.log" | grep -E -- "$2"; return 1; }
}
ok_line() { # <name> <label regex>
  grep -qE "^ok - .*$2" "$work/$1.log" || { echo "no ok matching '$2'"; return 1; }
}
no_ok_line() { # <name> <label fragment>
  ! grep -F -- "$2" "$work/$1.log" | grep '^ok - '
}

# Without Faito's network
variant no-network "$(sed "s/c4-infra\.faito/$NO_NETWORK/g" tests/0007-dev.sh)" tickee guard
check "without Faito's network: the copy names $NO_NETWORK" grep -qF "$NO_NETWORK" "$work/no-network.log"
check "without Faito's network: a KO names it and register-app.sh --app faito" \
  ko_naming no-network "$NO_NETWORK .*register-app.sh --app faito" "network $NO_NETWORK not found"
check "without Faito's network: the negative check by name KOs, naming it" \
  ko_naming no-network "AC-07: from $NO_NETWORK, $STANDIN:7080 can't be reached by name" "network $NO_NETWORK not found"
check "without Faito's network: the negative check by address KOs, naming it" \
  ko_naming no-network "AC-07: from $NO_NETWORK, $BY_ADDRESS" "network $NO_NETWORK not found"
check "without Faito's network: no ok from it" no_ok_line no-network "AC-07: from $NO_NETWORK"
check "without Faito's network: the dev alias check KOs, naming it" \
  ko_naming no-network "dev: the reverse proxy has no INFRA_HOST alias on $NO_NETWORK" "reverse proxy on $NO_NETWORK"
check "without Faito's network: exit 1" exited no-network 1

# Without the probe image
variant no-image "$(sed "s/alpine:3/$NO_IMAGE/g" tests/0007-dev.sh)" tickee
check "without the probe image: the control KOs, naming it" ko_naming no-image "control: from c4-infra.tickee" "$NO_IMAGE"
check "without the probe image: the negative check by name KOs, naming it" \
  ko_naming no-image "can't be reached by name" "$NO_IMAGE"
check "without the probe image: the negative check by address KOs, naming it" \
  ko_naming no-image "$BY_ADDRESS" "$NO_IMAGE"
check "without the probe image: exit 1" exited no-image 1

# A docker wrapper first on PATH: CONNECT_FAITO connects the stand-in to Faito's network once it
# starts; FAIL_DOCKER fails `docker ps … name=^<stand-in>$` and `docker compose config --format json`
real_docker=$(command -v docker)
mkdir -p "$work/bin"
cat > "$work/bin/docker" <<EOF
#!$BASH
if [ -n "\${FAIL_DOCKER:-}" ]; then
  case "\$*" in
    'ps -aq -f name=^$STANDIN\$') echo "0034's docker: ps refused" >&2; exit 1 ;;
    'compose config --format json') echo "0034's docker: compose config refused" >&2; exit 1 ;;
  esac
fi
$(printf '%q' "$real_docker") "\$@"
status=\$?
if [ -n "\${CONNECT_FAITO:-}" ] && [ \$status -eq 0 ] && [[ "\$*" == "run "*" -d --name $STANDIN "* ]]; then
  $(printf '%q' "$real_docker") network connect c4-infra.faito $STANDIN > /dev/null
fi
exit \$status
EOF
chmod +x "$work/bin/docker"

# The stand-in on Faito's network too
CONNECT_FAITO=1 PATH="$work/bin:$PATH" variant faito-too "$(cat tests/0007-dev.sh)" tickee
check "the stand-in on Faito's network too: by name, KO succeeded" \
  ko_naming faito-too "AC-07: from c4-infra.faito, $STANDIN:7080 can't be reached by name" succeeded
check "the stand-in on Faito's network too: at one of its addresses, KO succeeded" \
  ko_naming faito-too "$BY_ADDRESS" succeeded
check "the stand-in on Faito's network too: exit 1" exited faito-too 1

# Docker failing
FAIL_DOCKER=1 PATH="$work/bin:$PATH" variant docker-fails "$(cat tests/0007-dev.sh)" tickee guard
check "docker failing: the stand-in's removal KOs, naming docker ps" ko_naming docker-fails "the stand-in is removed" "docker ps"
check "docker failing: the dev alias check KOs, naming docker compose config" \
  ko_naming docker-fails "dev: the reverse proxy has no INFRA_HOST alias" "docker compose config"
check "docker failing: the negative check by name still passes (the real isolation)" \
  ok_line docker-fails "AC-07: from c4-infra.faito, $STANDIN:7080 can't be reached by name"
check "docker failing: the negative check by address still passes" ok_line docker-fails "$BY_ADDRESS"
check "docker failing: exit 1" exited docker-fails 1
finish
