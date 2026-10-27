#!/usr/bin/env bash
# 0009: on a stand-in demo host, the master realm Keycloak creates from keycloak-import/ (AC-02 to
# AC-10, demo side):
#
#   - the first deployment, on an empty database: neither the administrator's nor Mailpit's SMTP
#     password appears in the host's `ps -eo args`, `docker top` of Keycloak nor deploy.sh's output
#     (AC-07); the master realm has the demo host's SMTP settings, Verify email on, Forgot password
#     off, its administrator admin@<INFRA_HOST>, verified, and its Test connection works (AC-02, AC-09);
#     the registration account is created, and still may not change the master realm (AC-08);
#   - a second deployment, then the master realm's settings changed and Keycloak restarted: nothing
#     changes them back, no administrator logs in (AC-03);
#   - the administrator's address unverified and the account to repair: deploy.sh fails, naming the
#     pending action (AC-10);
#   - a new MAILPIT_SMTP_PASSWORD: Test connection fails until the master realm's password is set as
#     docs/demo-setup.md says (AC-06);
#   - ops replaces admin: the deployment and the master realm's mails go on (AC-05);
#   - last, Keycloak's database re-created with docs/demo-setup.md's command: the next deployment
#     creates the master realm and the registration account again, a realm registers (AC-04).
#
#   bash tests/0009-master-realm.stand-in.sh      (bash tests/run.sh --all runs it)
#
# As tests/0006-bootstrap-admin-replaced.stand-in.sh: the Keycloak image is the one up.sh builds here,
# loaded into the stand-in; Let's Encrypt is kept out; passwords travel in environments and on stdin.
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/stand-in-host.sh

DIR=/root/c4-infra
APPS=/root/apps
CLIENT=c4-infra-registration
HOST=infra.c4-soft.com
# docs/demo-setup.md's re-creation of Keycloak's database, run here in the stack's directory
RECREATE='docker compose rm -sf keycloak keycloak-import keycloak-db && docker volume rm c4-infra_keycloak_db'

umask 077
work=$(mktemp -d)
samplers=()
cleanup() {
  touch "$work/sample.stop"
  [ ${#samplers[@]} -eq 0 ] || wait "${samplers[@]}" 2> /dev/null
  stand_in_down
  rm -rf "$work"
}
trap cleanup EXIT

OPS_PASSWORD=$(openssl rand -hex 16)
NEXT_SMTP_PASSWORD=$(openssl rand -hex 16)
export OPS_PASSWORD NEXT_SMTP_PASSWORD

# <log> <command…>: in the stack's directory on the stand-in, stdin closed, the output into
# $work/<log>, the exit status into $status
in_stack() {
  local log=$1
  shift
  MSYS_NO_PATHCONV=1 docker exec "$STAND_IN_NAME" bash -c 'cd "$1" && shift && "$@" < /dev/null' sh "$DIR" "$@" \
    > "$work/$log" 2>&1
  status=$?
}
exited() { # <expected status> <log>
  [ "$status" -eq "$1" ] || { echo "exit $status:"; tail -n 25 "$work/$2"; return 1; }
}
says() { # <log> <text>
  grep -qF -- "$2" "$work/$1" || { echo "output:"; tail -n 25 "$work/$1"; return 1; }
}
never_says() { # <log> <text>
  ! grep -qF -- "$2" "$work/$1" || { echo "output:"; tail -n 25 "$work/$1"; return 1; }
}
refused_with() { # <expected text> <command…>
  local expected=$1 output
  shift
  if output=$("$@" 2>&1); then
    echo "succeeded:"
    printf '%s\n' "$output" | tail -n 5
    return 1
  fi
  grep -qF -- "$expected" <<< "$output" || { echo "failed without '$expected':"; printf '%s\n' "$output" | tail -n 5; return 1; }
}

# The admin CLI in the stand-in's Keycloak, as the administrator of the stand-in's .env (as data)
# or ops ($OPS_PASSWORD); -i passes stdin, which the caller redirects
kc_as() { # admin|ops [-i] <kcadm args…>
  local who=$1 io=""
  shift
  if [ "${1:-}" = -i ]; then
    io=-i
    shift
  fi
  MSYS_NO_PATHCONV=1 docker exec $io -e OPS_PASSWORD "$STAND_IN_NAME" bash -c '
    cd "$1"; who=$2; io=$3; shift 3
    value() { grep -m1 "^$1=" .env | cut -d= -f2-; }
    if [ "$who" = admin ]; then
      user=$(value KC_BOOTSTRAP_ADMIN_USERNAME)
      KC_CLI_PASSWORD=$(value KC_BOOTSTRAP_ADMIN_PASSWORD)
    else
      user=ops
      KC_CLI_PASSWORD=$OPS_PASSWORD
    fi
    export KC_CLI_PASSWORD
    docker exec $io -e KC_CLI_PASSWORD c4-infra.keycloak /opt/keycloak/bin/kcadm.sh "$@" \
      --no-config --server http://localhost:8080/auth --realm master --user "$user"' \
    sh "$DIR" "$who" "$io" "$@"
}
# The registration account (the secret of the stand-in's .env), as registrations log in
as_account() { # <kcadm args…>
  MSYS_NO_PATHCONV=1 docker exec "$STAND_IN_NAME" bash -c '
    cd "$1"; shift
    KC_CLI_CLIENT_SECRET=$(grep -m1 "^KC_REGISTRATION_CLIENT_SECRET=" .env | cut -d= -f2-)
    export KC_CLI_CLIENT_SECRET
    docker exec -e KC_CLI_CLIENT_SECRET c4-infra.keycloak sh -c '\''
      session=/dev/shm/c4-registration-0009.kcadm
      trap "rm -f $session" EXIT
      /opt/keycloak/bin/kcadm.sh config credentials --config "$session" --server http://localhost:8080/auth \
        --realm master --client "$1" > /dev/null || exit 1
      shift
      /opt/keycloak/bin/kcadm.sh "$@" --config "$session"'\'' sh "$@"' sh "$DIR" "$CLIENT" "$@" < /dev/null
}
master() { kc_as "$1" get realms/master < /dev/null 2> /dev/null; } # <who>
master_is() { # <jq filter> <expected>
  local value
  value=$(master admin | jq -c "$1") || { echo "get realms/master failed"; return 1; }
  [ "$value" = "$2" ] || { echo "$1 is $value, not $2"; return 1; }
}
user_field() { # <who> <username> <jq filter>
  kc_as "$1" get users -q "username=$2" -q exact=true < /dev/null 2> /dev/null | jq -c ".[0] | $3"
}
# The master realm's Test connection with its stored settings (the password masked: Keycloak's own)
test_connection() { # <who>
  master "$1" | jq -c .smtpServer | kc_as "$1" -i create testSMTPConnection -f -
}
keycloak_healthy() {
  local waited=0
  until [ "$(stand_in_exec docker inspect -f '{{.State.Health.Status}}' c4-infra.keycloak 2> /dev/null | tr -d '\r')" = healthy ]; do
    [ "$waited" -lt 240 ] || { echo "not healthy after $waited s"; return 1; }
    sleep 3
    waited=$((waited + 3))
  done
}

check "the stand-in host starts" stand_in_up
check "the Keycloak and proxy images built here are loaded into it" stand_in_load_image c4-infra/keycloak c4-infra/reverse-proxy
stand_in_exec rm -rf "$DIR" "$APPS"
check "the deployment's files are sent (demo/deploy-files.txt)" stand_in_send "$DIR"
check "keycloak-import/master-realm.json is among them" stand_in_exec test -f "$DIR/keycloak-import/master-realm.json"
check ".env is written there by demo/write-env.sh" stand_in_env "$DIR"

# AC-07: both passwords, from the stand-in's .env, into a file the detector reads (mode 600)
stand_in_exec sh -c 'grep -E "^(KC_BOOTSTRAP_ADMIN_PASSWORD|MAILPIT_SMTP_PASSWORD)=" "$1" | cut -d= -f2-' sh "$DIR/.env" \
  | tr -d '\r' > "$work/secrets"
check "AC-07: both passwords are read from the stand-in's .env" test "$(grep -c . "$work/secrets")" = 2
leaks_into() { # <source name>
  if grep -F -f "$work/secrets" > /dev/null; then echo "$1" >> "$work/leaks"; fi
}
leaks_into control < "$work/secrets"
check "AC-07: the detector catches them when they are there" grep -qx control "$work/leaks"
rm -f "$work/leaks"
# each sample counted, and those that saw the deployment (the host) and Keycloak's JVM (docker top)
sample() {
  local count=0 host=0 keycloak=0 list
  while [ ! -f "$work/sample.stop" ]; do
    list=$(stand_in_exec ps -eo args 2> /dev/null)
    printf '%s\n' "$list" | leaks_into "the host's ps -eo args"
    case $list in *deploy.sh*) host=$((host + 1)) ;; esac
    list=$(stand_in_exec docker top c4-infra.keycloak -eo pid,args 2> /dev/null)
    printf '%s\n' "$list" | leaks_into "docker top"
    case $list in *java*) keycloak=$((keycloak + 1)) ;; esac
    count=$((count + 1))
    echo "$count $host $keycloak" > "$work/samples"
  done
}
sample &
samplers+=($!)

in_stack deploy-1.log bash ./demo/deploy.sh
touch "$work/sample.stop"
wait "${samplers[@]}"
samplers=()
check "the first deployment, on an empty database, exits 0" exited 0 deploy-1.log
check "keycloak-import imported the master realm" grep -qF "Realm 'master' imported" <(stand_in_exec docker logs c4-infra.keycloak-import 2>&1)
check "deploy.sh creates the registration account" says deploy-1.log "Registration account $CLIENT: created"
check "with the administrator of .env" says deploy-1.log "the bootstrap administrator of .env"
no_leak() {
  [ ! -s "$work/leaks" ] || { echo "a password appears in:"; sort "$work/leaks" | uniq -c; return 1; }
}
read -r samples host_seen keycloak_seen < "$work/samples"
check "AC-07: ps -eo args saw the deployment at work ($host_seen of $samples samples)" test "${host_seen:-0}" -ge 1
check "AC-07: docker top saw Keycloak's JVM ($keycloak_seen of $samples samples)" test "${keycloak_seen:-0}" -ge 1
check "AC-07: neither password in ps -eo args nor docker top" no_leak
check "AC-07: nor in deploy.sh's output" test -z "$(grep -F -f "$work/secrets" "$work/deploy-1.log")"
check "AC-07: nor in Keycloak's log" test -z "$(stand_in_exec docker logs c4-infra.keycloak 2>&1 | grep -F -f "$work/secrets")"
check "AC-07: nor in keycloak-import's log (0012: it reads them)" \
  test -z "$(stand_in_exec docker logs c4-infra.keycloak-import 2>&1 | grep -F -f "$work/secrets")"

# AC-02, AC-09
check "AC-02: SMTP mailpit:1025 without TLS, Mailpit's user" master_is \
  '.smtpServer | [.host, .port, .starttls, .ssl, .auth, .user, .from]' \
  "[\"mailpit\",\"1025\",\"false\",\"false\",\"true\",\"mailpit\",\"noreply@$HOST\"]"
check "AC-02: Verify email on" master_is .verifyEmail true
check "AC-09: Forgot password off on the demo host" master_is .resetPasswordAllowed false
# the master realm's login page, as the console opens it (its PKCE parameters), fetched by Caddy's
# container from Keycloak on their network
login_page() {
  local url="http://keycloak:8080/auth/realms/master/protocol/openid-connect/auth?client_id=security-admin-console"
  url+="&response_type=code&scope=openid&redirect_uri=https%3A%2F%2F$HOST%2Fauth%2Fadmin%2Fmaster%2Fconsole%2F"
  url+="&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM&code_challenge_method=S256"
  stand_in_exec docker exec c4-infra.reverse-proxy wget -q -O - "$url"
}
login_page > "$work/login.html" 2>&1
check "AC-09: the master realm's login page shows its form" grep -qF login-actions/authenticate "$work/login.html"
check "AC-09: without a Forgot password? link" test -z "$(grep -F login-actions/reset-credentials "$work/login.html")"
check "AC-02: the administrator's address is admin@$HOST, verified" \
  test "$(user_field admin admin '[.email, .emailVerified]')" = "[\"admin@$HOST\",true]"
check "AC-02: the master realm's Test connection succeeds" test_connection admin

# AC-08
check "AC-08: the registration account may not change the master realm (403)" \
  refused_with 403 as_account update realms/master -s displayName=x

# AC-03
in_stack deploy-2.log bash ./demo/deploy.sh
check "AC-03: a second deployment exits 0" exited 0 deploy-2.log
check "AC-03: with no administrator's login" never_says deploy-2.log "Logged in as"
check "AC-03: the master realm's SMTP host changed by the administrator" \
  kc_as admin update realms/master -s smtpServer.host=other.example < /dev/null
# since 0012 the import is keycloak-import's, which each start of the stack runs: a deployment
skipped_imports() {
  stand_in_exec docker logs c4-infra.keycloak-import 2>&1 | grep -cF "Realm 'master' already exists. Import skipped"
}
skipped_before=$(skipped_imports)
in_stack deploy-2b.log bash ./demo/deploy.sh
check "AC-03: another deployment exits 0 (keycloak-import runs again)" exited 0 deploy-2b.log
check "AC-03: Keycloak is healthy" keycloak_healthy
check "AC-03: it skipped the import" test "$(skipped_imports)" -gt "$skipped_before"
check "AC-03: the master realm keeps the changed host" master_is .smtpServer.host '"other.example"'
kc_as admin update realms/master -s smtpServer.host=mailpit < /dev/null > /dev/null 2>&1

# An administrator ops (a verified address), for AC-10 and AC-05
create_ops() {
  printf '{"username":"ops","enabled":true,"email":"ops@%s","emailVerified":true,"credentials":[{"type":"password","value":"%s","temporary":false}]}' \
    "$HOST" "$OPS_PASSWORD" | kc_as admin -i create users -f - > /dev/null \
    && kc_as admin add-roles --uusername ops --rolename admin < /dev/null
}
check "the administrator creates ops, with a verified address" create_ops
check "ops logs in" kc_as ops get realms/master --fields realm < /dev/null
admin_id=$(user_field ops admin .id | tr -d '"')

# AC-10
check "AC-10: the administrator's address made unverified" \
  kc_as ops update "users/$admin_id" -s emailVerified=false < /dev/null
client_id=$(kc_as ops get clients -q "clientId=$CLIENT" --fields id < /dev/null 2> /dev/null | jq -r '.[0].id')
check "AC-10: the registration account deleted, so that deploy.sh needs an administrator" \
  kc_as ops delete "clients/$client_id" < /dev/null
in_stack deploy-3.log bash ./demo/deploy.sh
check "AC-10: deploy.sh fails" exited 1 deploy-3.log
check "AC-10: naming the administrator's pending action" says deploy-3.log "Keycloak refuses admin for a pending required action"
restore_admin() {
  kc_as ops update "users/$admin_id" -s emailVerified=true -s 'requiredActions=[]' < /dev/null
}
check "AC-10: the address verified again and the action removed" restore_admin
in_stack deploy-4.log bash ./demo/deploy.sh
check "AC-10: deploy.sh then exits 0" exited 0 deploy-4.log
check "AC-10: and creates the registration account again" says deploy-4.log "Registration account $CLIENT: created"

# AC-06: a new Mailpit SMTP password, the workflow's way (.env rewritten by write-env.sh)
rewrite_env() {
  stand_in_exec -i sh -c 'cat > /tmp/write-env.sh' < demo/write-env.sh || return 1
  MSYS_NO_PATHCONV=1 docker exec -e NEXT_SMTP_PASSWORD "$STAND_IN_NAME" bash -c '
    set -e
    cd "$1"
    value() { local line; line=$(grep -m1 "^$1=" .env); line=${line#*=}; printf "%s" "${line//\$\$/\$}"; }
    export INFRA_HOST=$(value INFRA_HOST) KC_IMAGE=$(value KC_IMAGE) PROXY_IMAGE=$(value PROXY_IMAGE) KC_ADMIN_USERNAME=$(value KC_BOOTSTRAP_ADMIN_USERNAME)
    export KC_ADMIN_PASSWORD=$(value KC_BOOTSTRAP_ADMIN_PASSWORD) KC_DB_PASSWORD=$(value KC_DB_PASSWORD)
    export KC_REGISTRATION_CLIENT_SECRET=$(value KC_REGISTRATION_CLIENT_SECRET)
    export RABBITMQ_ADMIN_PASSWORD=$(value RABBITMQ_ADMIN_PASSWORD) MAILPIT_SMTP_PASSWORD=$NEXT_SMTP_PASSWORD
    export MAILPIT_UI_PASSWORD_HASH=$(value MAILPIT_UI_PASSWORD_HASH) GRAFANA_ADMIN_PASSWORD=$(value GRAFANA_ADMIN_PASSWORD)
    bash /tmp/write-env.sh .env
    rm -f /tmp/write-env.sh
    sed -i "s/^COMPOSE_FILE=.*/&:compose.no-acme.yml/" .env' sh "$DIR"
}
check "AC-06: .env rewritten by write-env.sh with a new MAILPIT_SMTP_PASSWORD" rewrite_env
in_stack deploy-5.log bash ./demo/deploy.sh
check "AC-06: the deployment exits 0" exited 0 deploy-5.log
check "AC-06: the master realm's Test connection now fails (its former password)" \
  refused_with "Failed to send email" test_connection admin
# docs/demo-setup.md: the new password typed in the master realm's Email settings; here the admin
# API's equivalent, the password from this shell's environment into JSON on stdin
set_smtp_password() {
  master admin | jq -c '.smtpServer | .password = env.NEXT_SMTP_PASSWORD | {smtpServer: .}' \
    | kc_as admin -i update realms/master -f -
}
check "AC-06: the master realm's SMTP password set to the new one" set_smtp_password
check "AC-06: its Test connection succeeds again" test_connection admin

# AC-05: ops replaces admin
check "AC-05: ops deletes the administrator of .env" kc_as ops delete "users/$admin_id" < /dev/null
in_stack deploy-6.log bash ./demo/deploy.sh
check "AC-05: the next deployment exits 0" exited 0 deploy-6.log
check "AC-05: with no administrator's login" never_says deploy-6.log "Logged in as"
check "AC-05: the master realm's Test connection, as ops, succeeds" test_connection ops

# AC-04: Keycloak's database re-created with docs/demo-setup.md's command
check "AC-04: docs/demo-setup.md holds the re-creation command" grep -qF -- "$RECREATE" docs/demo-setup.md
in_stack recreate.log bash -c "$RECREATE"
check "AC-04: Keycloak's database is removed" exited 0 recreate.log
in_stack deploy-7.log bash ./demo/deploy.sh
check "AC-04: the next deployment exits 0" exited 0 deploy-7.log
check "AC-04: keycloak-import imported the master realm again" grep -qF "Realm 'master' imported" <(stand_in_exec docker logs c4-infra.keycloak-import 2>&1)
check "AC-04: deploy.sh creates the registration account again" says deploy-7.log "Registration account $CLIENT: created"
check "AC-04: the master realm has its SMTP settings" master_is .smtpServer.host '"mailpit"'
check "AC-04: and delivers with the current password" test_connection admin
stand_in_exec mkdir -p "$APPS"
printf '{"realm":"faito","enabled":true}\n' | stand_in_exec -i sh -c 'cat > "$1"' sh "$APPS/faito-realm.json"
in_stack register.log bash ./register-app.sh --app faito --realm "$APPS/faito-realm.json"
check "AC-04: a registration imports its realm" says register.log "Importing realm faito"
finish
