#!/usr/bin/env bash
# Writes ./.env once, with the settings of the shared dev stack and generated passwords. An entry
# already there is never overwritten: a fresh clone and an older checkout converge on the same file.
set -euo pipefail
cd "$(dirname "$0")"

touch .env

# Appends "KEY=value" to .env only if KEY is not defined there yet.
add() {
  grep -q "^${1%%=*}=" .env || echo "$1" >> .env
}

# Origin of the shared services (Keycloak, Mailpit, Grafana, RabbitMQ): the one host name that the
# browser, the JVMs running on the host and the containers all resolve.
add "INFRA_HOST=host.docker.internal"
# Each application gets its own origin, https://<app>.${APPS_DOMAIN}/ (browsers resolve *.localhost)
add "APPS_DOMAIN=dev.localhost"
# nginx in dev, caddy on the demo host: tells register-app.sh which kind of server block to install
add "PROXY=nginx"
add "TZ=Pacific/Tahiti"

add "KC_LOG_LEVEL=INFO"
add "KC_BOOTSTRAP_ADMIN_USERNAME=admin"
# "secret" on purpose, as before the stack was shared: the projects' scripts and docs rely on it
add "KC_BOOTSTRAP_ADMIN_PASSWORD=secret"
add "KC_DB_PASSWORD=$(openssl rand -hex 16)"

add "RABBITMQ_ADMIN_USER=admin"
add "RABBITMQ_ADMIN_PASSWORD=$(openssl rand -hex 16)"

# The realm exports embed the SMTP password in clear: a non-secret value on purpose
add "MAILPIT_SMTP_USER=mailpit"
add "MAILPIT_SMTP_PASSWORD=secret"
