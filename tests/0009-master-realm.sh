#!/usr/bin/env bash
# 0009: the master realm Keycloak creates in dev (AC-1, AC-3, AC-9, AC-10), in a throwaway Keycloak
# of the stack's image (start-dev on a file database, no published port) given what the dev model
# gives the stack's Keycloak for that import: its variables (never KC_DB_*), keycloak-import/, the
# local CA and host.docker.internal. Its mails go to this workstation's Mailpit. Then demo/write-env.sh's
# refusal of the values the import can't take (no Docker).
#
#   bash tests/0009-master-realm.sh
#
# Needs the dev stack running (Mailpit), the image c4-infra/keycloak (up.sh builds it) and jq.
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

IMAGE=c4-infra/keycloak
NAME=c4-infra.0009-master
SERVER=http://localhost:8080/auth
KCADM=/opt/keycloak/bin/kcadm.sh
MAILPIT_API=http://127.0.0.1:8025/mailpit/api/v1
export MSYS_NO_PATHCONV=1

host_path() {
  if command -v cygpath > /dev/null; then cygpath -w "$1"; else printf '%s' "$1"; fi
}

umask 077
work=$(mktemp -d)
trap 'docker rm -f "$NAME" > /dev/null 2>&1; rm -rf "$work"' EXIT

# The dev model's Keycloak: the variables the import reads (never KC_DB_*), and the CA it trusts
check "the dev model is read (compose.yml + compose.dev.yml, .env)" \
  docker compose -f compose.yml -f compose.dev.yml --env-file .env config --format json -o "$(host_path "$work/dev.json")"
jq -r '.services.keycloak.environment | to_entries[]
  | select(.key | test("^(C4_MASTER_.*|INFRA_HOST|MAILPIT_SMTP_.*|KC_TRUSTSTORE_PATHS)$")) | "\(.key)=\(.value)"' \
  < "$work/dev.json" > "$work/kc.env"
check "its Keycloak gets the import's variables, and no KC_BOOTSTRAP_ADMIN_* (Keycloak would abort its start)" \
  test "$(jq -r '.services.keycloak.environment | keys | map(select(startswith("C4_MASTER_") or startswith("KC_BOOTSTRAP_ADMIN_"))) | sort | join(" ")' < "$work/dev.json")" \
  = "C4_MASTER_ADMIN_PASSWORD C4_MASTER_ADMIN_USERNAME C4_MASTER_RESET_PASSWORD_ALLOWED C4_MASTER_SMTP_HOST C4_MASTER_SMTP_STARTTLS"
value() { sed -n "s/^$1=//p" "$work/kc.env"; }
check "and INFRA_HOST (host.docker.internal)" test "$(value INFRA_HOST)" = host.docker.internal
# The throwaway's own host name (its administrator's address, the sender's): the test finds and
# removes its own mails in this workstation's Mailpit, whatever else lands there
INFRA_HOST=verif-0009-$(openssl rand -hex 4).test
sed -i "s/^INFRA_HOST=.*/INFRA_HOST=$INFRA_HOST/" "$work/kc.env"
KC_CLI_PASSWORD=$(value C4_MASTER_ADMIN_PASSWORD)
ADMIN=$(value C4_MASTER_ADMIN_USERNAME)
export KC_CLI_PASSWORD

admin() {
  docker exec -e KC_CLI_PASSWORD "$NAME" "$KCADM" "$@" --no-config --server "$SERVER" --realm master --user "$ADMIN" < /dev/null
}
admin_in() {
  docker exec -i -e KC_CLI_PASSWORD "$NAME" "$KCADM" "$@" --no-config --server "$SERVER" --realm master --user "$ADMIN"
}
ready() {
  local waited=0
  until docker exec "$NAME" java -cp /opt/keycloak/healthcheck HealthCheck http://localhost:9000/auth/health/ready > /dev/null 2>&1; do
    if [ -z "$(docker ps -q -f "name=^$NAME$")" ] || [ "$waited" -ge 240 ]; then
      echo "not ready ($waited s); its log:"
      docker logs --tail 5 "$NAME" 2>&1
      return 1
    fi
    sleep 2
    waited=$((waited + 2))
  done
}
master_is() { # <jq filter> <expected>
  local value
  value=$(admin get realms/master 2> /dev/null | jq -c "$1") || { echo "get realms/master failed"; return 1; }
  [ "$value" = "$2" ] || { echo "$1 is $value, not $2"; return 1; }
}

docker rm -f "$NAME" > /dev/null 2>&1
check "a throwaway Keycloak starts on an empty database, importing keycloak-import/" \
  docker run -d --name "$NAME" --env-file "$(host_path "$work/kc.env")" --add-host host.docker.internal:host-gateway \
  -v "$(host_path "$PWD/keycloak-import"):/opt/keycloak/data/import:ro" \
  -v "$(host_path "$PWD/certs/ca.crt"):/opt/keycloak/certs/ca.crt:ro" \
  "$IMAGE" start-dev --db=dev-file --import-realm
check "it is ready" ready
check "it imported the master realm" grep -qF "Realm 'master' imported" <(docker logs "$NAME" 2>&1)

# AC-1
check "AC-1: the administrator logs in with the admin CLI (verifyEmail on)" admin get realms/master --fields realm
check "AC-1: SMTP host.docker.internal:1025, STARTTLS, Mailpit's user" master_is \
  '.smtpServer | [.host, .port, .starttls, .ssl, .auth, .user, .from]' \
  "[\"host.docker.internal\",\"1025\",\"true\",\"false\",\"true\",\"mailpit\",\"noreply@$INFRA_HOST\"]"
check "AC-1: its password stored (masked by Keycloak)" master_is .smtpServer.password '"**********"'
check "AC-1: verifyEmail on" master_is .verifyEmail true
check "AC-1: as created by Keycloak itself: displayName Keycloak, accessTokenLifespan 60" master_is \
  '[.displayName, .accessTokenLifespan]' '["Keycloak",60]'
address() {
  [ "$(admin get users -q "username=$ADMIN" 2> /dev/null | jq -c '.[0] | [.email, .emailVerified, .requiredActions]')" \
    = "[\"admin@$INFRA_HOST\",true,[]]" ]
}
check "AC-1: the administrator's address is admin@$INFRA_HOST, verified" address

mailpit_count() { curl -fsS "$MAILPIT_API/search?query=to:admin@$INFRA_HOST" | jq -r .messages_count; }
before=$(mailpit_count)
check "AC-1: this workstation's Mailpit answers ($before mail(s) to admin@$INFRA_HOST)" test -n "$before"
test_connection() {
  admin get realms/master 2> /dev/null | jq -c .smtpServer | admin_in create testSMTPConnection -f -
}
check "AC-1: the master realm's Test connection succeeds (Keycloak's stored password)" test_connection
delivered() {
  local waited=0
  until [ "$(mailpit_count)" -gt "$before" ]; do
    [ "$waited" -lt 10 ] || { echo "still $before mail(s) after $waited s"; return 1; }
    sleep 1
    waited=$((waited + 1))
  done
}
check "AC-1: its mail is in Mailpit" delivered
# the test's mails removed: those to the throwaway's own address
curl -fsS -X DELETE "$MAILPIT_API/search?query=to:admin@$INFRA_HOST" > /dev/null

# AC-9 (dev)
check "AC-9: Forgot password on" master_is .resetPasswordAllowed true
login_page() {
  local url="$SERVER/realms/master/protocol/openid-connect/auth?client_id=security-admin-console&response_type=code&scope=openid"
  url+="&redirect_uri=http%3A%2F%2Flocalhost%3A8080%2Fauth%2Fadmin%2Fmaster%2Fconsole%2F"
  # the console's PKCE parameters, without which its login page isn't shown
  url+="&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM&code_challenge_method=S256"
  docker run --rm --network "container:$NAME" alpine:3 wget -q -O - "$url"
}
check "AC-9: the master realm's login page links reset-credentials" grep -qF login-actions/reset-credentials <(login_page)

# AC-10 (the admin CLI side)
create_unverified() {
  printf '{"username":"verif-unverified","enabled":true,"email":"verif-unverified@%s","emailVerified":false,"credentials":[{"type":"password","value":"%s","temporary":false}]}' \
    "$INFRA_HOST" "$KC_CLI_PASSWORD" | admin_in create users -f - > /dev/null \
    && admin add-roles --uusername verif-unverified --rolename admin
}
check "AC-10: an administrator whose address isn't verified" create_unverified
refused() {
  local output
  if output=$(docker exec -e KC_CLI_PASSWORD "$NAME" "$KCADM" get realms/master --fields realm --no-config \
    --server "$SERVER" --realm master --user verif-unverified < /dev/null 2>&1); then
    echo "logged in"
    return 1
  fi
  grep -qF "Account is not fully set up" <<< "$output" || { printf '%s\n' "$output" | tail -n 2; return 1; }
}
check "AC-10: its admin CLI login is refused (Account is not fully set up)" refused

# AC-3: a master realm that exists keeps its settings
check "AC-3: the master realm's SMTP host changed by an administrator" admin update realms/master -s smtpServer.host=other.example
docker restart "$NAME" > /dev/null
check "AC-3: Keycloak restarted is ready" ready
check "AC-3: it skipped the import" grep -qF "Realm 'master' already exists. Import skipped" <(docker logs "$NAME" 2>&1)
check "AC-3: the master realm keeps the changed host" master_is .smtpServer.host '"other.example"'

# REQ-6: the file holds names, not values
no_value() {
  local name value
  for name in C4_MASTER_ADMIN_PASSWORD MAILPIT_SMTP_PASSWORD; do
    value=$(value "$name")
    [ -n "$value" ] || continue
    ! grep -qF -- "\"$value\"" keycloak-import/master-realm.json || { echo "$name's value is in the file"; return 1; }
  done
  grep -qF '"${MAILPIT_SMTP_PASSWORD}"' keycloak-import/master-realm.json
}
check "REQ-6: keycloak-import/master-realm.json holds the passwords' names, not their values" no_value

# demo/write-env.sh (the demo host's .env) refuses what the import can't take, naming it
write_env() { # <NAME=value>…: the demo environment's settings with dummy values, overridden
  env INFRA_HOST=infra.c4-soft.com KC_IMAGE=dummy KC_ADMIN_PASSWORD=dummy KC_DB_PASSWORD=dummy \
    KC_REGISTRATION_CLIENT_SECRET=dummy RABBITMQ_ADMIN_PASSWORD=dummy MAILPIT_SMTP_PASSWORD=dummy \
    MAILPIT_UI_PASSWORD_HASH=dummy GRAFANA_ADMIN_PASSWORD=dummy "$@" bash demo/write-env.sh "$work/demo.env"
}
refused_naming() { # <name> <NAME=value>…
  local name=$1 output
  shift
  if output=$(write_env "$@" 2>&1); then
    echo "accepted"
    return 1
  fi
  grep -qF -- "$name" <<< "$output" || { printf '%s\n' "$output"; return 1; }
}
check "write-env.sh accepts plain values" write_env 'KC_ADMIN_PASSWORD=a$b+/=c'
check "write-env.sh refuses a double quote in KC_ADMIN_PASSWORD" refused_naming KC_ADMIN_PASSWORD 'KC_ADMIN_PASSWORD=a"b'
check "write-env.sh refuses a backslash in MAILPIT_SMTP_PASSWORD" refused_naming MAILPIT_SMTP_PASSWORD 'MAILPIT_SMTP_PASSWORD=a\b'
check "write-env.sh refuses a tab in KC_ADMIN_USERNAME" refused_naming KC_ADMIN_USERNAME "KC_ADMIN_USERNAME=a$(printf '\t')b"
check "write-env.sh refuses an INFRA_HOST that isn't a host name" refused_naming INFRA_HOST 'INFRA_HOST=a"b.test'
finish
