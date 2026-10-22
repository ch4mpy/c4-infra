#!/usr/bin/env bash
# Prepares the demo host, a fresh Ubuntu VPS, and its accounts (intent 0002): one for the shared
# stack, one per application. Needs root; run it once with c4-infra, then once per application:
#
#   vps-bootstrap.sh c4-infra '<public key>'     the shared stack's account c4-infra, the only one
#                                                 in the docker group, with ~/c4-infra
#   vps-bootstrap.sh app <name> '<public key>'   the application <name>'s account: outside the
#                                                 docker group, in the group c4-apps, which may run
#                                                 `sudo c4-app` only; with ~/<name>/
#
# OVH's images give no SSH access to root but a sudoer, ubuntu: copy the script over and run it with
# sudo, so that sudo can ask for its password on the terminal (docs/demo-setup.md):
#   scp demo/vps-bootstrap.sh ubuntu@<vps-ip>:/tmp/
#   ssh -t ubuntu@<vps-ip> "sudo bash /tmp/vps-bootstrap.sh c4-infra '$(cat c4-infra-demo.pub)'"
#
# Each run also prepares the host, idempotently: Docker from its official repository and
# unattended-upgrades when Docker is missing; ufw, jq and rsync; the firewall (22, 80 and 443 in
# only; no new outgoing connection from the applications' accounts but on the loopback); the group
# c4-apps; /etc/sudoers.d/c4-infra, checked by visudo before it is installed. Keys are appended,
# never replaced, as `restrict <key>`: no forwarding and no terminal, the workflows run commands
# (the demo operator logs in as ubuntu).
set -euo pipefail

usage() {
  echo "Usage: $0 c4-infra '<public key>' | app <name> '<public key>'" >&2
  exit 1
}

case "${1:-}" in
  c4-infra)
    account=c4-infra
    shift
    ;;
  app)
    [ $# -ge 2 ] || usage
    account=$2
    shift 2
    if ! [[ $account =~ ^[a-z][a-z0-9-]*$ ]] || [ "$account" = c4-infra ]; then
      echo "An application's account is named after its registry entry (lowercase letters, digits and '-'), not '$account'" >&2
      exit 1
    fi
    ;;
  *) usage ;;
esac

# ssh concatenates the arguments of a remote command into a single string, so the public key may
# reach us split into words: join them back instead of relying on the caller's quoting.
PUBLIC_KEY="$*"
case "$PUBLIC_KEY" in
  ssh-* | ecdsa-* | sk-*) ;;
  *)
    echo "Expected the contents of a public key file, got: ${PUBLIC_KEY:-nothing}" >&2
    exit 1
    ;;
esac
if [[ $PUBLIC_KEY == *$'\n'* ]]; then
  echo "Expected one public key, on one line" >&2
  exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must run as root: either as root@<vps-ip>, or through sudo (see the header)" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
if ! command -v docker > /dev/null; then
  apt-get update
  apt-get install -y ca-certificates curl unattended-upgrades

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
  dpkg-reconfigure -f noninteractive unattended-upgrades
fi
# what the deployments use on the host: the firewall, jq (c4-app's checks, intent 0007), rsync
# (the workflows' uploads, c4-app's staging copies)
missing=()
for tool in ufw jq rsync; do
  command -v "$tool" > /dev/null || missing+=("$tool")
done
if [ ${#missing[@]} -gt 0 ]; then
  apt-get update
  apt-get install -y "${missing[@]}"
fi

# The applications' group: the sudo rule below and the firewall's owner match name it
getent group c4-apps > /dev/null || groupadd c4-apps

# sudo: the applications' accounts run c4-app only, as root, which acts on their own project; the
# shared stack's account installs c4-app (demo/deploy.sh), one exact command line
sudoers=$(mktemp)
cat > "$sudoers" <<'EOF'
# Written by c4-infra's demo/vps-bootstrap.sh (intent 0002)
%c4-apps ALL=(root) NOPASSWD: /usr/local/sbin/c4-app
c4-infra ALL=(root) NOPASSWD: /usr/bin/install -o root -g root -m 0755 /home/c4-infra/c4-infra/demo/c4-app /usr/local/sbin/c4-app
EOF
if ! visudo -cf "$sudoers" > /dev/null; then
  rm -f "$sudoers"
  echo "visudo refuses the sudo rules: /etc/sudoers.d/c4-infra left as it is" >&2
  exit 1
fi
install -m 0440 -o root -g root "$sudoers" /etc/sudoers.d/c4-infra
rm -f "$sudoers"
# root's staging copies of the applications' files (c4-app)
install -d -m 0755 -o root -g root /var/lib/c4-apps

# Firewall: SSH and HTTP(S) in only (Docker publishes 80 and 443 for Caddy, nothing else); and the
# applications' accounts open no connection of their own but on the loopback: their ssh and rsync
# are inbound, so that they can't reach the containers' addresses from the host either. In ufw's
# before*.rules, before the filter table's COMMIT, added once.
ufw default deny incoming > /dev/null
ufw default allow outgoing > /dev/null
ufw allow OpenSSH > /dev/null
ufw allow 80/tcp > /dev/null
ufw allow 443/tcp > /dev/null
add_output_rule() { # <rules file> <chain>
  local file=$1 rule="-A $2 -m owner --gid-owner c4-apps --suppl-groups -m conntrack --ctstate NEW ! -o lo -j REJECT"
  local next
  grep -qxF -- "$rule" "$file" && return 0
  next=$(mktemp)
  awk -v rule="$rule" '
    /^\*filter/ { filter = 1 }
    filter && !added && $0 == "COMMIT" {
      print "# c4-infra (demo/vps-bootstrap.sh): no new outgoing connection of the applications'\'' accounts but on the loopback"
      print rule
      added = 1
    }
    { print }
    END { if (!added) exit 1 }' "$file" > "$next" || {
    rm -f "$next"
    echo "$file has no *filter table ending in COMMIT: the rule for c4-apps is not added" >&2
    return 1
  }
  cat "$next" > "$file"
  rm -f "$next"
}
add_output_rule /etc/ufw/before.rules ufw-before-output
add_output_rule /etc/ufw/before6.rules ufw6-before-output
ufw --force enable > /dev/null
ufw reload > /dev/null

# The account, key-only SSH; its home closed to the others
home=/home/$account
if id "$account" > /dev/null 2>&1; then
  groups=" $(id -nG "$account") "
  if [ "$account" = c4-infra ]; then
    usermod -aG docker c4-infra
  elif [[ $groups != *" c4-apps "* ]] || [[ $groups == *" docker "* ]]; then
    # an account this script didn't create (ubuntu, a system user…) never becomes an application's
    echo "$account exists, and is not an application's account (in c4-apps, outside docker): left as it is" >&2
    exit 1
  fi
elif [ "$account" = c4-infra ]; then
  useradd --create-home --shell /bin/bash --groups docker c4-infra
else
  useradd --create-home --shell /bin/bash --groups c4-apps "$account"
fi
chmod 0750 "$home"
install -d -m 0700 -o "$account" -g "$account" "$home/.ssh"
touch "$home/.ssh/authorized_keys"
grep -qxF "restrict $PUBLIC_KEY" "$home/.ssh/authorized_keys" \
  || echo "restrict $PUBLIC_KEY" >> "$home/.ssh/authorized_keys"
chmod 0600 "$home/.ssh/authorized_keys"
chown "$account:$account" "$home/.ssh/authorized_keys"
# the deployment's directory: ~/c4-infra for the shared stack, ~/<name>/ for an application
install -d -m 0750 -o "$account" -g "$account" "$home/$account"

echo "Done. $account's workflow can now deploy as $account@$(hostname -I | awk '{print $1}')"
