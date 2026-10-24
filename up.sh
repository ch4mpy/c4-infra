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

# The application registry: no two applications share a number (their port block), a name, a realm,
# a theme, a RabbitMQ user or a host name
if ! bash ./registry.sh check; then
  echo "The registry is invalid (above): fix registry.txt, then run $0 again." >&2
  exit 1
fi

bash ./env.sh

# The master realm's import (keycloak-import/, intent 0009) takes these values of .env into its JSON
# as they are: a double quote, a backslash or a control character makes that import fail on an
# empty database (keycloak-import exits 1, intent 0012), and Keycloak doesn't start
# (demo/write-env.sh refuses them on the demo host)
(
  source ./registry.sh
  for key in KC_BOOTSTRAP_ADMIN_USERNAME KC_BOOTSTRAP_ADMIN_PASSWORD MAILPIT_SMTP_PASSWORD; do
    stack_env_read value "$key"
    case $value in
      *'"'* | *'\'* | *[[:cntrl:]]*)
        echo "$key of .env holds a double quote, a backslash or a control character, which the master realm's import can't take: choose another value, then run $0 again. On a stack whose master realm exists already (started before intent 0009, or since), Keycloak keeps the former value: type the new one in its console too (README.md, \"The master realm\")." >&2
        exit 1
        ;;
    esac
  done
) || exit 1

certificate_before=$(cat certs/tls.crt 2> /dev/null | cksum)
bash ./certs/make-certs.sh
certificate_after=$(cat certs/tls.crt | cksum)

# compose.apps.yml (COMPOSE_FILE): the shared services on each registered application's network,
# before any compose call (intent 0007)
bash ./networks.sh compose-file

# A project still running its own copy of these services holds their ports: name it rather than let
# compose fail on the first one. The ports are the ones the compose files publish (compose.dev.yml).
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

[ -f caddy/html/index.html ] || bash ./register-app.sh --index-only

# The master realm's import (intent 0009), which Keycloak reads as its own user, not root: readable
# by all, whatever mode the checkout has (a umask 077 makes it 600 on Linux); no secret in it
chmod -R a+rX keycloak-import

docker compose up -d --build --wait
# compose recreates nothing when only a mounted file changed (caddy/Caddyfile, caddy/env/*.caddy
# after a pull): reload Caddy (graceful). A configuration it refuses leaves the previous one
# serving: say so and stop, never restart it (it would start on the refused one, every site down)
if ! output=$(MSYS_NO_PATHCONV=1 docker exec c4-infra.reverse-proxy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile 2>&1); then
  printf '%s\n' "$output" | tail -n 5 >&2
  echo "The reverse proxy refuses its configuration (above): it keeps serving its previous configuration. Fix caddy/ (or the site of caddy/apps/ it names), then run $0 again." >&2
  exit 1
fi

# The services read the certificate at startup, and compose recreates nothing when only a mounted
# file changed
if [ "$certificate_before" != "$certificate_after" ]; then
  docker compose restart reverse-proxy mailpit
  docker compose up -d --wait
fi

# The account registrations log in as, with Keycloak healthy (--wait above): created when missing,
# its secret set to .env's, the registry's realms granted to it; an administrator is only needed then
bash ./registration-account.sh ensure
