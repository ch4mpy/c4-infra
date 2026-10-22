#!/usr/bin/env bash
# One-time preparation of a fresh Ubuntu VPS for the shared demo host. It needs root privileges:
#   ssh root@<vps-ip> 'bash -s' < demo/vps-bootstrap.sh "$(cat c4-infra-demo.pub)"
# On an image where root has no SSH access but a sudoer does (OVH ships `ubuntu`), copy the
# script over and run it with sudo, so that sudo can prompt for a password on the terminal:
#   scp demo/vps-bootstrap.sh ubuntu@<vps-ip>:/tmp/
#   ssh -t ubuntu@<vps-ip> "sudo bash /tmp/vps-bootstrap.sh '$(cat c4-infra-demo.pub)'"
# Installs Docker from its official repository, creates the `deploy` user that every deployment
# workflow connects as (c4-infra's and each application's: member of the docker group, key-only
# SSH), and opens 22/80/443 only.
#
# Run it again with another public key to authorize one more workflow (an application's): keys are
# appended, never replaced.
set -euo pipefail

# ssh concatenates the arguments of a remote command into a single string, so the public key
# reaches us split into words: join them back instead of relying on the caller's quoting.
DEPLOY_PUBLIC_KEY="${*:-}"
if [ -z "$DEPLOY_PUBLIC_KEY" ]; then
  echo "The SSH public key of a deploy workflow is expected as argument" >&2
  exit 1
fi
case "$DEPLOY_PUBLIC_KEY" in
  ssh-* | ecdsa-* | sk-*) ;;
  *)
    echo "Expected the contents of a public key file, got: $DEPLOY_PUBLIC_KEY" >&2
    exit 1
    ;;
esac

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must run as root: either as root@<vps-ip>, or through sudo (see the header)" >&2
  exit 1
fi

if ! command -v docker > /dev/null; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y ca-certificates curl ufw unattended-upgrades

  # Docker Engine + Compose plugin, per https://docs.docker.com/engine/install/ubuntu/
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker

  # firewall: SSH + HTTP(S) only (Docker publishes 80/443 for Caddy, nothing else is published)
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow OpenSSH
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw --force enable

  dpkg-reconfigure -f noninteractive unattended-upgrades
fi

# deploy user
if ! id deploy > /dev/null 2>&1; then
  useradd --create-home --shell /bin/bash --groups docker deploy
fi
install -d -m 0700 -o deploy -g deploy /home/deploy/.ssh
touch /home/deploy/.ssh/authorized_keys
grep -qxF "$DEPLOY_PUBLIC_KEY" /home/deploy/.ssh/authorized_keys \
  || echo "$DEPLOY_PUBLIC_KEY" >> /home/deploy/.ssh/authorized_keys
chmod 0600 /home/deploy/.ssh/authorized_keys
chown deploy:deploy /home/deploy/.ssh/authorized_keys
install -d -o deploy -g deploy /home/deploy/c4-infra

echo "Done. The workflows can now deploy as deploy@$(hostname -I | awk '{print $1}')"
