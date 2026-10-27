#!/usr/bin/env bash
# 0006: a registration doesn't depend on the bootstrap administrator's password (RQ-01, RQ-05; AC-01's
# "password changed" variant). With a KC_BOOTSTRAP_ADMIN_PASSWORD in .env that is no longer the one
# Keycloak holds, as after "change the password" in the admin console, Faito's registration still
# finds its realm.
#
#   bash tests/0006-registration-without-bootstrap-password.sh
#
# Runs a copy of the registration (the root's scripts, registry.txt and .env) from a temporary
# directory whose .env holds another bootstrap password: the shared Keycloak's administrator is left
# alone. Realm faito exists (Faito's deploy-dev.sh): one read, nothing changed.
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

FAITO_REALM=${FAITO_DIR:-../faito}/keycloak/import/faito-realm.json

# the copy of .env holds the stack's secrets: private, and removed whatever happens
umask 077
work=$(mktemp -d)
chmod 700 "$work"
trap 'rm -rf "$work"' EXIT

cp ./*.sh registry.txt tlds-alpha-by-domain.txt "$work/"
# .env, with another bootstrap password (echo is a builtin: the value is on no command line)
{
  grep -v '^KC_BOOTSTRAP_ADMIN_PASSWORD=' .env
  echo "KC_BOOTSTRAP_ADMIN_PASSWORD=$(openssl rand -hex 16)"
} > "$work/.env"

password_differs() { # compared in this shell: neither value goes on a command line
  local before after
  before=$(grep -m1 '^KC_BOOTSTRAP_ADMIN_PASSWORD=' .env)
  after=$(grep -m1 '^KC_BOOTSTRAP_ADMIN_PASSWORD=' "$work/.env")
  [ -n "$after" ] && [ "$before" != "$after" ]
}
check "Faito's realm export is there ($FAITO_REALM)" test -f "$FAITO_REALM"
check "the copy's bootstrap password is not .env's" password_differs

bash "$work/register-app.sh" --app faito --realm "$FAITO_REALM" > "$work/register.out" 2>&1 < /dev/null
status=$?

registered() {
  [ "$status" -eq 0 ] || { echo "exit $status:"; tail -n 20 "$work/register.out"; return 1; }
}
said() { # <line>
  grep -qxF -- "$1" "$work/register.out" || { echo "register-app.sh printed:"; tail -n 20 "$work/register.out"; return 1; }
}
check "Faito's registration exits 0 with another bootstrap password in .env" registered
check "it finds realm faito, left as it is" said "Realm faito: already in Keycloak, left as it is"
finish
