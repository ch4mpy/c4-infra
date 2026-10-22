#!/usr/bin/env bash
# Writes the demo host's .env from the deployment's environment: the workflow's settings and the
# secrets of its GitHub environment `demo` (docs/demo-setup.md). Run by
# .github/workflows/deploy-demo.yml on the runner, before the upload: the file is mode 600 there,
# and `rsync -a` keeps that mode on the host.
#
#   bash demo/write-env.sh <file>      fails, naming each one, when a setting or a secret is missing
#   bash demo/write-env.sh --required  the names of the secrets it requires, one per line
#
# Reads INFRA_HOST and KC_IMAGE (required), KC_ADMIN_USERNAME (default admin), and the secrets that
# --required prints.
set -euo pipefail

SECRETS=(KC_ADMIN_PASSWORD KC_DB_PASSWORD KC_REGISTRATION_CLIENT_SECRET RABBITMQ_ADMIN_PASSWORD
  MAILPIT_SMTP_PASSWORD MAILPIT_UI_PASSWORD_HASH GRAFANA_ADMIN_PASSWORD)

case "${1:-}" in
  --required)
    printf '%s\n' "${SECRETS[@]}"
    exit 0
    ;;
  '' | -*)
    echo "Usage: bash $0 <file> | --required" >&2
    exit 2
    ;;
esac
file=$1

# fail here, by name, rather than deploy a Grafana without admin password or a Caddy basic_auth
# with an empty hash because one secret was never created
missing=()
for name in INFRA_HOST KC_IMAGE "${SECRETS[@]}"; do
  [ -n "${!name:-}" ] || missing+=("$name")
done
if [ ${#missing[@]} -gt 0 ]; then
  echo "Missing settings or secrets of the demo environment: ${missing[*]}" >&2
  exit 1
fi

# compose interpolates $ in .env values: escape it (the Mailpit bcrypt hash has some)
esc() { printf '%s' "${!1}" | sed 's/\$/$$/g'; }

# the file holding every secret is never readable by others, from its creation on
umask 077
{
  echo "INFRA_ENV=demo"
  echo "COMPOSE_FILE=compose.yml:compose.demo.yml"
  echo "COMPOSE_PATH_SEPARATOR=:"
  echo "INFRA_HOST=$INFRA_HOST"
  echo "TZ=Pacific/Tahiti"
  echo "KC_IMAGE=$KC_IMAGE"
  echo "KC_LOG_LEVEL=INFO"
  echo "KC_BOOTSTRAP_ADMIN_USERNAME=${KC_ADMIN_USERNAME:-admin}"
  echo "KC_BOOTSTRAP_ADMIN_PASSWORD=$(esc KC_ADMIN_PASSWORD)"
  echo "KC_DB_PASSWORD=$(esc KC_DB_PASSWORD)"
  # the account registrations log in as (registration-account.sh, which deploy.sh runs)
  echo "KC_REGISTRATION_CLIENT_ID=c4-infra-registration"
  echo "KC_REGISTRATION_CLIENT_SECRET=$(esc KC_REGISTRATION_CLIENT_SECRET)"
  echo "RABBITMQ_ADMIN_USER=admin"
  echo "RABBITMQ_ADMIN_PASSWORD=$(esc RABBITMQ_ADMIN_PASSWORD)"
  echo "MAILPIT_SMTP_USER=mailpit"
  echo "MAILPIT_SMTP_PASSWORD=$(esc MAILPIT_SMTP_PASSWORD)"
  echo "MAILPIT_UI_PASSWORD_HASH=$(esc MAILPIT_UI_PASSWORD_HASH)"
  echo "GRAFANA_ADMIN_PASSWORD=$(esc GRAFANA_ADMIN_PASSWORD)"
} > "$file"
# an existing file keeps its mode through ">": set it
chmod 600 "$file"
