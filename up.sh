#!/usr/bin/env bash
# Starts the shared dev stack, or brings it up to date. Idempotent: each application's deploy-dev.sh
# runs it before registering itself.
set -euo pipefail
cd "$(dirname "$0")"

# compose.yml publishes every port on 127.0.0.1 only: this machine's browser, JVMs and Node
# processes reach the stack through host.docker.internal, which must resolve there. Docker Desktop
# can write the LAN address for that name in the hosts file: stop before starting anything.
addresses=$(
  if command -v getent > /dev/null; then
    getent ahostsv4 host.docker.internal | awk '{ print $1 }'
  else
    powershell.exe -NoProfile -Command "[System.Net.Dns]::GetHostAddresses('host.docker.internal') | Where-Object AddressFamily -eq 'InterNetwork' | ForEach-Object IPAddressToString" 2> /dev/null | tr -d '\r'
  fi | sort -u
) || true
if [ "$addresses" != 127.0.0.1 ]; then
  shown=${addresses:-nothing}
  shown=${shown//$'\n'/, }
  cat >&2 <<EOF
host.docker.internal resolves to $shown, not 127.0.0.1. The stack publishes its ports on the loopback only: this machine's browser and JVMs would not reach it.
To fix it:
  - turn off Docker Desktop's option (Settings > General, "Add the *.docker.internal names to the host's etc/hosts file");
  - keep the single line "127.0.0.1 host.docker.internal" in C:\Windows\System32\drivers\etc\hosts (/etc/hosts elsewhere);
  - then run $0 again.
EOF
  exit 1
fi

bash ./env.sh
certificate_before=$(cat certs/tls.crt 2> /dev/null | cksum)
bash ./certs/make-certs.sh
certificate_after=$(cat certs/tls.crt | cksum)

# A project still running its own copy of these services holds their ports: name it rather than let
# compose fail on the first one. The ports are the ones compose.yml publishes.
conflicts=()
for port in $(docker compose config | sed -n 's/^ *published: "\([0-9]*\)"$/\1/p'); do
  # docker's own filter: it also matches a port inside a published range (4317-4318->...)
  for name in $(docker ps --filter "publish=$port" --format '{{.Names}}'); do
    case "$name" in
      c4-infra.*) ;;
      *) conflicts+=("$name (port $port)") ;;
    esac
  done
done
if [ ${#conflicts[@]} -gt 0 ]; then
  echo "These containers hold ports of the shared stack:" >&2
  printf '  %s\n' "${conflicts[@]}" | sort -u >&2
  echo "Stop them first (docker stop <name>...), then run $0 again." >&2
  exit 1
fi

[ -f nginx/html/index.html ] || bash ./register-app.sh --index-only

docker compose up -d --build --wait
# nginx doesn't watch its configuration, and compose recreates nothing when only a mounted file
# changed: reload it (graceful), or restart the proxy when a reload can't apply it (a changed pid
# path, for instance)
MSYS_NO_PATHCONV=1 docker exec c4-infra.reverse-proxy nginx -c /etc/nginx/c4-infra/nginx.conf -s reload 2> /dev/null \
  || docker restart c4-infra.reverse-proxy > /dev/null

# The services read the certificate at startup, and compose recreates nothing when only a mounted
# file changed
if [ "$certificate_before" != "$certificate_after" ]; then
  docker compose restart reverse-proxy mailpit
  docker compose up -d --wait
fi
