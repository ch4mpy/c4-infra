#!/usr/bin/env bash
# Starts the shared dev stack, or brings it up to date. Idempotent: each application's deploy-dev.sh
# runs it before registering itself.
set -euo pipefail
cd "$(dirname "$0")"

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
