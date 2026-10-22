#!/usr/bin/env bash
# Pins the demo host's key before any connection to it: a deployment workflow (c4-infra's, and each
# application's: docs/migration.md, "On the demo host") runs it on its runner before the ssh agent
# receives the private key, and before any ssh or rsync.
#
#   VPS_KNOWN_HOSTS=<the host's known_hosts line(s)> bash demo/trust-host-key.sh
#
# VPS_KNOWN_HOSTS is the secret of the same name (docs/demo-setup.md, step 4). Without it the
# deployment fails here, with a workflow error: no trust on first use, which would send every secret
# of the deployment to whatever host answers.
set -euo pipefail

if [ -z "${VPS_KNOWN_HOSTS:-}" ]; then
  echo "::error::VPS_KNOWN_HOSTS is not set: the deployment connects only to a host whose key is pinned (docs/demo-setup.md, step 4, \"Host key\")"
  exit 1
fi

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
printf '%s\n' "$VPS_KNOWN_HOSTS" >> "$HOME/.ssh/known_hosts"
