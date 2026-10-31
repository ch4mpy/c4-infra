#!/usr/bin/env bash
# A stand-in demo host for the tests: an Ubuntu container running its own Docker and sshd
# (tests/stand-in-host/), which receives exactly what the demo deployment sends and runs its
# commands. Source it, or run its self-test:
#
#   bash tests/lib/stand-in-host.sh selftest
#
#   stand_in_up                      builds the image and starts the stand-in, waits for its dockerd,
#                                    and removes an earlier run's containers, volumes and networks
#                                    (the pulled images stay; STAND_IN_FRESH=1: them too)
#   stand_in_exec [-i] <command…>    runs the command in the stand-in, as root; -i passes stdin, which
#                                    the caller always redirects
#   stand_in_load_image <image>…     copies images of this machine into the stand-in's Docker
#   stand_in_probe                   the isolation tests' probe (tests/fixtures/0007/probe/: an echo on
#                                    :7080, curl, nmap, nc) as c4-test/probe in the stand-in's Docker
#   stand_in_send <dir>              sends the files of demo/deploy-files.txt into <dir>, as the
#                                    deployment does
#   stand_in_env <dir>               writes <dir>/.env with demo/write-env.sh, run inside the
#                                    stand-in (a Linux shell, as the workflow's runner), with a random
#                                    value for each secret `write-env.sh --required` names; then keeps
#                                    Let's Encrypt out and gives Caddy its local authority
#                                    (compose.no-acme.yml)
#   stand_in_accounts <app>…         the demo host's accounts (intent 0002), as docs/demo-setup.md
#                                    prepares them: a key pair per account, generated inside the
#                                    stand-in ($STAND_IN_KEYS), `vps-bootstrap.sh c4-infra` and
#                                    `vps-bootstrap.sh app <app>` for each; then the shared stack
#                                    deployed as c4-infra over ssh, as the workflow does: the files of
#                                    demo/deploy-files.txt and .env (stand_in_send, stand_in_env)
#                                    rsynced to /home/c4-infra/c4-infra, then demo/deploy.sh there
#                                    (which installs c4-app). The Keycloak image is this machine's.
#   stand_in_ssh [-i] <account> <command>
#                                    runs the command over ssh to 127.0.0.1 inside the stand-in, as
#                                    <account>, with its key (stand_in_accounts), the host key pinned;
#                                    -i passes stdin, which the caller always redirects
#   stand_in_ssh_command <account>   that ssh command line (for rsync -e), inside the stand-in
#   stand_in_ca_cert                 the root certificate (PEM, no key) of the local authority the
#                                    stand-in's Caddy issues every site's certificate from, once the
#                                    stack is deployed; exit 1, saying why, when the stack or the
#                                    authority isn't there
#   stand_in_https <host> <path> [curl option…]
#                                    one request to https://<host><path> from inside the stand-in,
#                                    every host and port sent to its Caddy, that root the only trust
#                                    anchor; first waits up to 30 s for Caddy and the site's
#                                    certificate (GET https://<host>/, no cookie, until the handshake
#                                    verifies, each attempt bounded to 5 s); curl's exit status, 28
#                                    when the site still accepts without answering at the end of the
#                                    wait, or stand_in_ca_cert's failures.
#                                    The caller's paths (-o, -D, -c, -b) are the stand-in's
#   stand_in_down                    stops and removes the stand-in (its Docker volume stays: the
#                                    pulled images)
#
# HTTPS (intent 0035): on the stand-in, Caddy issues each site's certificate from its own local
# authority (tests/stand-in-host/caddy-env/, which compose.no-acme.yml mounts), never from Let's
# Encrypt; the real demo host's configuration is unchanged. Nothing trusts that root but a client
# given it: stand_in_ca_cert's, or stand_in_https's own copy, removed after its request. A client of
# its own reaches a site by its name from inside the stand-in, which publishes no port: `curl
# --connect-to ::127.0.0.1: --cacert <root> --capath <an empty directory> https://<site>/…` (an
# empty --capath, or curl also reads the system's). The authority's keys stay in the stand-in's
# caddy_data volume, inside $STAND_IN_VOLUME, until the next stand_in_up removes it.
#
# The Docker volume $STAND_IN_VOLUME (c4-infra-stand-in-docker) holds the stand-in's /var/lib/docker
# between runs. STAND_IN_NAME and STAND_IN_VOLUME, from the environment, name another stand-in, beside
# the one another checkout's tests run: stand_in_up removes the container of its name, and two dockerds
# can't share a volume (e.g. STAND_IN_NAME=c4-infra-stand-in-0009
# STAND_IN_VOLUME=c4-infra-stand-in-0009-docker).

STAND_IN_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
STAND_IN_NAME=${STAND_IN_NAME:-c4-infra-stand-in}
STAND_IN_IMAGE=c4-infra/stand-in-host
STAND_IN_VOLUME=${STAND_IN_VOLUME:-c4-infra-stand-in-docker}
# only the stand-ins' own names: docker rm -f and docker volume rm act on them
if ! [[ $STAND_IN_NAME =~ ^c4-infra-stand-in[a-z0-9-]*$ && $STAND_IN_VOLUME =~ ^c4-infra-stand-in[a-z0-9-]*$ ]]; then
  echo "STAND_IN_NAME and STAND_IN_VOLUME start with c4-infra-stand-in (lowercase letters, digits, '-')" >&2
  exit 1
fi
STAND_IN_CADDY_IMAGE=caddy:2.11.4-alpine
# inside the stand-in: the accounts' keys and the pinned host key (stand_in_accounts)
STAND_IN_KEYS=/root/stand-in-keys

# the docker CLI of Windows wants a Windows path for a build context
_stand_in_host_path() {
  if command -v cygpath > /dev/null; then cygpath -w "$1"; else printf '%s' "$1"; fi
}

stand_in_exec() {
  local options=()
  if [ "${1:-}" = -i ]; then
    options=(-i)
    shift
  fi
  MSYS_NO_PATHCONV=1 docker exec "${options[@]}" "$STAND_IN_NAME" "$@"
}

stand_in_up() {
  local waited=0
  docker build -q -t "$STAND_IN_IMAGE" "$(_stand_in_host_path "$STAND_IN_ROOT/tests/stand-in-host")" > /dev/null \
    || { echo "stand_in_up: the image doesn't build" >&2; return 1; }
  docker rm -f "$STAND_IN_NAME" > /dev/null 2>&1 || true
  if [ "${STAND_IN_FRESH:-0}" = 1 ]; then
    docker volume rm "$STAND_IN_VOLUME" > /dev/null 2>&1 || true
  fi
  MSYS_NO_PATHCONV=1 docker run -d --privileged --name "$STAND_IN_NAME" --hostname vps \
    -v "$STAND_IN_VOLUME:/var/lib/docker" "$STAND_IN_IMAGE" > /dev/null \
    || { echo "stand_in_up: the stand-in doesn't start" >&2; return 1; }
  until stand_in_exec docker info > /dev/null 2>&1; do
    if [ "$waited" -ge 60 ]; then
      echo "stand_in_up: no dockerd in the stand-in after 60 s; its log:" >&2
      stand_in_exec tail -n 20 /var/log/dockerd.log >&2
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  # a fresh host but for the pulled images: an earlier run's containers (restarted by its dockerd),
  # volumes (Keycloak's database, with that run's passwords) and networks are removed
  stand_in_exec sh -c 'docker ps -aq | xargs -r docker rm -f > /dev/null
    docker volume ls -q | xargs -r docker volume rm > /dev/null
    docker network prune -f > /dev/null'
}

stand_in_load_image() {
  local image
  for image in "$@"; do
    docker save "$image" | stand_in_exec -i docker load -q > /dev/null \
      || { echo "stand_in_load_image: $image not loaded" >&2; return 1; }
  done
}

# Built on this machine, when it lacks the image or the fixture changed (the label c4-infra.fixture holds
# its content's hash: a build would ask the registry for the base image even then), then copied in unless
# the stand-in's volume already holds it: the stand-in's own Docker fails to resolve a name now and then
# (intent 0020)
stand_in_probe() {
  local fixture=$STAND_IN_ROOT/tests/fixtures/0007/probe hash
  hash=$(cd "$fixture" && find . -type f | LC_ALL=C sort | while IFS= read -r file; do
    echo "$file"
    cat "$file"
  done | cksum | cut -d' ' -f1)
  if [ "$(docker image inspect -f '{{index .Config.Labels "c4-infra.fixture"}}' c4-test/probe 2> /dev/null)" != "$hash" ]; then
    docker build -q --label "c4-infra.fixture=$hash" -t c4-test/probe "$(_stand_in_host_path "$fixture")" > /dev/null \
      || { echo "stand_in_probe: c4-test/probe doesn't build on this machine (above)" >&2; return 1; }
  fi
  [ "$(stand_in_exec docker image inspect -f '{{index .Config.Labels "c4-infra.fixture"}}' c4-test/probe 2> /dev/null \
    | tr -d '\r')" = "$hash" ] || stand_in_load_image c4-test/probe
}

stand_in_send() { # <dir>
  stand_in_exec mkdir -p "$1" || return 1
  (cd "$STAND_IN_ROOT" && tar -cf - -T demo/deploy-files.txt) \
    | stand_in_exec -i tar -xf - --no-same-owner -C "$1"
}

# In a subshell: the generated secrets never reach the caller's environment
stand_in_env() ( # <dir>
  dir=$1
  options=()
  names=$(bash "$STAND_IN_ROOT/demo/write-env.sh" --required) || exit 1
  for name in $names; do
    if [[ $name == *_HASH ]]; then
      # a bcrypt hash of a random password; caddy reads the password on its stdin
      value=$(openssl rand -hex 16 | docker run --rm -i "$STAND_IN_CADDY_IMAGE" caddy hash-password) || exit 1
    else
      value=$(openssl rand -hex 16)
    fi
    export "$name=$value"
    # -e NAME, without a value: docker exec takes it from this environment, not the command line
    options+=(-e "$name")
  done
  export INFRA_HOST=infra.c4-soft.com KC_IMAGE=c4-infra/keycloak PROXY_IMAGE=c4-infra/reverse-proxy
  stand_in_exec -i sh -c 'cat > /tmp/write-env.sh' < "$STAND_IN_ROOT/demo/write-env.sh" || exit 1
  MSYS_NO_PATHCONV=1 docker exec "${options[@]}" -e INFRA_HOST -e KC_IMAGE -e PROXY_IMAGE "$STAND_IN_NAME" \
    bash /tmp/write-env.sh "$dir/.env" || exit 1
  stand_in_exec rm -f /tmp/write-env.sh
  stand_in_exec -i sh -c 'cat > "$1"' sh "$dir/compose.no-acme.yml" \
    < "$STAND_IN_ROOT/tests/stand-in-host/compose.no-acme.yml" || exit 1
  stand_in_exec sed -i 's/^COMPOSE_FILE=.*/&:compose.no-acme.yml/' "$dir/.env"
)

stand_in_ssh_command() { # <account>
  printf 'ssh -i %s/%s -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=%s/known_hosts' \
    "$STAND_IN_KEYS" "$1" "$STAND_IN_KEYS"
}

stand_in_ssh() { # [-i] <account> <command>
  local options=()
  if [ "${1:-}" = -i ]; then
    options=(-i)
    shift
  fi
  # word splitting of the ssh command line is wanted: it holds no space but between its words
  # shellcheck disable=SC2046
  stand_in_exec "${options[@]}" $(stand_in_ssh_command "$1") "$1@127.0.0.1" "$2"
}

# Why <account>'s key doesn't log in: the modes sshd checks, the key it holds, and the reason a
# one-shot sshd in debug mode (port 2222) gives
_stand_in_ssh_diagnose() { # <account>
  stand_in_exec bash -c '
    keys=$1 account=$2
    stat -c "%n %a %U:%G" "/home/$account" "/home/$account/.ssh" "/home/$account/.ssh/authorized_keys" "$keys/$account"
    ssh-keygen -lf "$keys/$account.pub"
    ssh-keygen -lf "/home/$account/.ssh/authorized_keys"
    /usr/sbin/sshd -d -p 2222 > /tmp/sshd-debug.log 2>&1 &
    sleep 1
    ssh -p 2222 -i "$keys/$account" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null "$account@127.0.0.1" true > /dev/null 2>&1
    wait
    grep -iE "refused|not allowed|bad ownership|authentication|key" /tmp/sshd-debug.log | tail -n 15' \
    sh "$STAND_IN_KEYS" "$1"
}

stand_in_accounts() { # <app>…
  local log=/root/stand-in-accounts.log
  # A fresh host's homes: the stand-in's dockerd restarts an earlier run's containers from its volume
  # before stand_in_up removes them, and their bind mounts recreate their sources, root-owned
  # (/home/c4-infra/c4-infra/caddy/…): sshd would then refuse the account's key
  stand_in_exec sh -c 'for dir in /home/c4-infra /var/lib/c4-apps "$@"; do
      case $dir in /*) ;; *) dir=/home/$dir ;; esac
      [ ! -e "$dir" ] || { echo "# an earlier run'\''s leftover, removed: $dir"; rm -rf "$dir"; }
    done' sh "$@" || return 1
  stand_in_exec -i sh -c 'cat > /tmp/vps-bootstrap.sh' < "$STAND_IN_ROOT/demo/vps-bootstrap.sh" || return 1
  # the keys, and the host's own key pinned for 127.0.0.1 (no ssh-keyscan); then the accounts
  stand_in_exec bash -c '
    set -e
    keys=$1 log=$2
    shift 2
    rm -rf "$keys"
    mkdir -m 700 "$keys"
    for key in /etc/ssh/ssh_host_*_key.pub; do
      printf "127.0.0.1 %s\n" "$(cut -d" " -f1,2 "$key")"
    done > "$keys/known_hosts"
    for account in c4-infra "$@"; do
      ssh-keygen -q -t ed25519 -N "" -f "$keys/$account" -C "$account-stand-in"
    done
    {
      bash /tmp/vps-bootstrap.sh c4-infra "$(cat "$keys/c4-infra.pub")"
      for app in "$@"; do
        bash /tmp/vps-bootstrap.sh app "$app" "$(cat "$keys/$app.pub")"
      done
    } > "$log" 2>&1 || { tail -n 20 "$log"; exit 1; }
    rm -f /tmp/vps-bootstrap.sh' sh "$STAND_IN_KEYS" "$log" "$@" || return 1
  stand_in_load_image c4-infra/keycloak c4-infra/reverse-proxy || return 1
  # the shared stack, as the workflow deploys it: its files and .env rsynced as c4-infra (rsync -a
  # keeps .env's mode 600), then demo/deploy.sh run there as c4-infra
  stand_in_exec rm -rf /root/c4-infra-upload
  stand_in_send /root/c4-infra-upload || return 1
  stand_in_env /root/c4-infra-upload || return 1
  stand_in_exec bash -c 'cd /root/c4-infra-upload && rsync -az -e "$1" ./ c4-infra@127.0.0.1:~/c4-infra/' \
    sh "$(stand_in_ssh_command c4-infra)" || { _stand_in_ssh_diagnose c4-infra; return 1; }
  stand_in_ssh c4-infra "cd ~/c4-infra && bash ./demo/deploy.sh < /dev/null > ~/deploy.log 2>&1" \
    || { stand_in_exec tail -n 30 /home/c4-infra/deploy.log; return 1; }
}

# Shell code for the stand-in: read_root <caller> prints the root of the proxy's local authority,
# waited for up to 10 s, or says why there is none and returns 1. Never reads its key.
_STAND_IN_ROOT_READER='
read_root() {
  if [ -z "$(docker ps -q -f "name=^c4-infra.reverse-proxy\$")" ]; then
    echo "$1: the stand-in runs no c4-infra.reverse-proxy (the stack isn'"'"'t deployed: stand_in_accounts)" >&2
    return 1
  fi
  for i in $(seq 1 50); do
    docker exec c4-infra.reverse-proxy sh -c "test -s \"\$0\" && cat \"\$0\"" \
      /data/caddy/pki/authorities/local/root.crt 2> /dev/null && return 0
    sleep 0.2
  done
  echo "$1: the stand-in'"'"'s Caddy has no local authority (is compose.no-acme.yml in the stack'"'"'s COMPOSE_FILE?)" >&2
  return 1
}
'

stand_in_ca_cert() {
  stand_in_exec sh -c "$_STAND_IN_ROOT_READER"'read_root stand_in_ca_cert' | tr -d '\r'
  return "${PIPESTATUS[0]}"
}

stand_in_https() { # <host> <path> [curl option…]
  stand_in_exec sh -c "$_STAND_IN_ROOT_READER"'
    host=$1 path=$2
    shift 2
    dir=$(mktemp -d /tmp/stand_in_https.XXXXXX) || exit 1
    trap "rm -rf $dir" EXIT
    mkdir "$dir/capath"
    read_root stand_in_https > "$dir/root.crt" || exit 1
    # after a start or a reload, Caddy listens (7 until then) and issues a site'"'"'s certificate (35) in the background;
    # a connection that opens and stalls times out (28): retried until the deadline, then returned (intent 0047)
    deadline=$(($(date +%s) + 30))
    while :; do
      curl -s -o /dev/null --max-time 5 --cacert "$dir/root.crt" --capath "$dir/capath" --connect-to ::127.0.0.1: \
        "https://$host/" && break
      status=$?
      case $status in
        7 | 35 | 28) [ "$(date +%s)" -lt "$deadline" ] || { [ "$status" -ne 28 ] || exit 28; break; } ;;
        *) break ;;
      esac
      sleep 0.2
    done
    curl -sS --cacert "$dir/root.crt" --capath "$dir/capath" --connect-to ::127.0.0.1: "$@" "https://$host$path"' \
    sh "$@"
}

stand_in_down() {
  # docker stop: the entrypoint stops dockerd, which stops its containers
  docker stop -t 60 "$STAND_IN_NAME" > /dev/null 2>&1 || true
  docker rm -f "$STAND_IN_NAME" > /dev/null 2>&1 || true
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -uo pipefail
  case "${1:-}" in
    selftest)
      source "$STAND_IN_ROOT/tests/lib/assert.sh"
      trap stand_in_down EXIT
      check "the stand-in host starts, with its dockerd" stand_in_up
      check "docker info succeeds inside" stand_in_exec docker info
      check "docker compose is there" stand_in_exec docker compose version
      check "sshd -t succeeds inside" stand_in_exec /usr/sbin/sshd -t
      check "its host name is vps" test "$(stand_in_exec hostname | tr -d '\r')" = vps
      stand_in_down
      check "it stops" test -z "$(docker ps -aq -f "name=^$STAND_IN_NAME\$")"
      finish
      ;;
    *)
      echo "Usage: bash $0 selftest" >&2
      exit 2
      ;;
  esac
fi
