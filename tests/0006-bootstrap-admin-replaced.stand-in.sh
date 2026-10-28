#!/usr/bin/env bash
# 0006: on a stand-in demo host, registrations survive the bootstrap administrator (AC-01, AC-05 and
# AC-06 on a Linux host):
#
#   - demo/deploy.sh creates the registration account, with the bootstrap administrator of .env;
#     Faito's realm registers;
#   - as the console invites to: a permanent administrator, ops, replaces the bootstrap one, which
#     ops deletes; Faito's registration with --reset-realms still deletes and imports its realm
#     (AC-01), and the next deployment needs no administrator;
#   - a rotation the workflow's way (AC-05): .env rewritten by demo/write-env.sh with a new
#     KC_REGISTRATION_CLIENT_SECRET; deploy.sh without KC_SETUP_ADMIN_* fails saying so, with them
#     (ops) it sets the new secret; a registration works, a login with the former secret fails;
#   - while that rotation and registrations run, neither secret appears in the host's `ps -eo args`,
#     `docker top` nor `docker inspect` of Keycloak (AC-06).
#
#   bash tests/0006-bootstrap-admin-replaced.stand-in.sh      (bash tests/run.sh --all runs it)
#
# As tests/0003-demo-deploy.stand-in.sh: the Keycloak image is the one up.sh builds here, loaded into
# the stand-in; Let's Encrypt is kept out (tests/stand-in-host/compose.no-acme.yml). The passwords
# and secrets travel in environments (docker exec -e NAME) and on stdin, never on a command line.
#
# covers: demo/ compose.yml compose.demo.yml register-app.sh registry.sh registry.txt routes.sh
# covers: networks.sh registration-account.sh tlds-alpha-by-domain.txt keycloak/ keycloak-import/
# covers: tests/stand-in-host/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/stand-in-host.sh

DIR=/root/c4-infra
APPS=/root/apps
FAITO_REALM=${FAITO_DIR:-../faito}/keycloak/import/faito-realm.json
CLIENT=c4-infra-registration

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

# The administrator ops' password, and the next registration secret: generated here, in variables
OPS_PASSWORD=$(openssl rand -hex 16)
NEXT_SECRET=$(openssl rand -hex 32)
export OPS_PASSWORD NEXT_SECRET

# <log> <command…>: in the stack's directory on the stand-in, stdin closed, the output into
# $work/<log>, the exit status into $status. KC_SETUP_ADMIN_* pass by name when set here.
in_stack() {
  local log=$1
  shift
  MSYS_NO_PATHCONV=1 docker exec ${KC_SETUP_ADMIN_USERNAME:+-e KC_SETUP_ADMIN_USERNAME -e KC_SETUP_ADMIN_PASSWORD} \
    "$STAND_IN_NAME" bash -c 'cd "$1" && shift && "$@" < /dev/null' sh "$DIR" "$@" > "$work/$log" 2>&1
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
fails() { # <command…>: the command fails
  ! "$@" > /dev/null 2>&1
}
# <expected text> <command…>: the command fails, and its output holds the text
refused_with() {
  local expected=$1 output
  shift
  if output=$("$@" 2>&1); then
    echo "succeeded:"
    printf '%s\n' "$output" | tail -n 5
    return 1
  fi
  grep -qF -- "$expected" <<< "$output" || { echo "failed without '$expected':"; printf '%s\n' "$output" | tail -n 5; return 1; }
}

# The admin CLI in the stand-in's Keycloak as an administrator: the bootstrap one (its password from
# the stand-in's .env, as data) or ops ($OPS_PASSWORD); -i passes stdin, which the caller redirects
kc_as() { # bootstrap|ops [-i] <kcadm args…>
  local who=$1 io=""
  shift
  if [ "${1:-}" = -i ]; then
    io=-i
    shift
  fi
  MSYS_NO_PATHCONV=1 docker exec $io -e OPS_PASSWORD "$STAND_IN_NAME" bash -c '
    cd "$1"; who=$2; io=$3; shift 3
    value() { grep -m1 "^$1=" .env | cut -d= -f2-; }
    if [ "$who" = bootstrap ]; then
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
user_id() { # bootstrap|ops <username>
  kc_as "$1" get users -q "username=$2" -q exact=true --fields id --format csv --noquotes < /dev/null 2> /dev/null | tr -d '\r'
}

# the registration secret of the stand-in's .env, into <file> (mode 600)
secret_into() { # <file>
  stand_in_exec sh -c 'grep -m1 "^KC_REGISTRATION_CLIENT_SECRET=" "$1" | cut -d= -f2-' sh "$DIR/.env" | tr -d '\r' > "$1"
  [ -s "$1" ]
}

check "the stand-in host starts" stand_in_up
check "the Keycloak and proxy images built here are loaded into it" stand_in_load_image c4-infra/keycloak c4-infra/reverse-proxy
stand_in_exec rm -rf "$DIR" "$APPS"
check "the deployment's files are sent (demo/deploy-files.txt)" stand_in_send "$DIR"
check "registration-account.sh is among them" stand_in_exec test -f "$DIR/registration-account.sh"
check ".env is written there by demo/write-env.sh" stand_in_env "$DIR"
check ".env names the registration account" stand_in_exec grep -qx "KC_REGISTRATION_CLIENT_ID=$CLIENT" "$DIR/.env"
check "the old secret is kept here" secret_into "$work/old-secret"

# The first deployment creates the account, with the bootstrap administrator
in_stack deploy-1.log bash ./demo/deploy.sh
check "deploy.sh exits 0" exited 0 deploy-1.log
check "deploy.sh creates the registration account" says deploy-1.log "Registration account $CLIENT: created"
check "with the bootstrap administrator of .env" says deploy-1.log "the bootstrap administrator of .env"

stand_in_exec mkdir -p "$APPS"
if [ -f "$FAITO_REALM" ]; then
  stand_in_exec -i sh -c 'cat > "$1"' sh "$APPS/faito-realm.json" < "$FAITO_REALM"
else
  echo "# $FAITO_REALM missing: a minimal realm faito instead"
  printf '{"realm":"faito","enabled":true}\n' | stand_in_exec -i sh -c 'cat > "$1"' sh "$APPS/faito-realm.json"
fi
in_stack register-1.log bash ./register-app.sh --app faito --realm "$APPS/faito-realm.json"
check "Faito's realm registers" exited 0 register-1.log
check "it is imported" says register-1.log "Importing realm faito"

# The console's invitation, followed: ops replaces the bootstrap administrator, then deletes it
check "the bootstrap administrator creates ops" kc_as bootstrap create users -s username=ops -s enabled=true < /dev/null
ops_id=$(user_id bootstrap ops)
check "ops has an id ($ops_id)" test -n "$ops_id"
set_ops_password() {
  printf '{"type":"password","value":"%s","temporary":false}' "$OPS_PASSWORD" \
    | kc_as bootstrap -i update "users/$ops_id/reset-password" -f -
}
check "its password is set from JSON on stdin" set_ops_password
check "it gets the master realm's admin role" kc_as bootstrap add-roles --uusername ops --rolename admin < /dev/null
admin_id=$(user_id ops admin)
check "ops logs in, and finds the bootstrap administrator ($admin_id)" test -n "$admin_id"
check "ops deletes the bootstrap administrator" kc_as ops delete "users/$admin_id" < /dev/null
check "the bootstrap administrator is gone" test -z "$(user_id ops admin)"
check "and doesn't log in any more" fails kc_as bootstrap get realms/master --fields realm < /dev/null

# AC-01
in_stack reset.log bash ./register-app.sh --app faito --realm "$APPS/faito-realm.json" --reset-realms
check "AC-01: Faito's registration with --reset-realms exits 0" exited 0 reset.log
check "AC-01: it deletes realm faito" says reset.log "Deleting realm faito"
check "AC-01: and imports it" says reset.log "Importing realm faito"
check "AC-01: realm faito is there" kc_as ops get realms/faito --fields realm < /dev/null
in_stack deploy-2.log bash ./demo/deploy.sh
check "the next deployment exits 0" exited 0 deploy-2.log
check "it finds the account up to date" says deploy-2.log "Registration account $CLIENT: up to date"
check "with no administrator" never_says deploy-2.log "Logged in as"

# AC-05 and AC-06: the rotation the workflow's way, while the samplers look for both secrets
cat "$work/old-secret" > "$work/secrets"
printf '%s\n' "$NEXT_SECRET" >> "$work/secrets"
leaks_into() { # <source name>: grep reads it all and prints nothing; a match recorded by name only
  if grep -F -f "$work/secrets" > /dev/null; then echo "$1" >> "$work/leaks"; fi
}
leaks_into control < "$work/secrets"
check "AC-06: the detector catches the secrets when they are there" grep -qx control "$work/leaks"
rm -f "$work/leaks"
sample_host() {
  local count=0 caught=0 list
  while [ ! -f "$work/sample.stop" ]; do
    list=$(stand_in_exec ps -eo args 2> /dev/null)
    printf '%s\n' "$list" | leaks_into "the host's ps -eo args"
    case $list in *register-app.sh* | *registration-account.sh*) caught=$((caught + 1)) ;; esac
    count=$((count + 1))
    echo "$count $caught" > "$work/host.samples"
  done
}
sample_keycloak() {
  local count=0 caught=0 top
  while [ ! -f "$work/sample.stop" ]; do
    top=$(stand_in_exec docker top c4-infra.keycloak -eo pid,args 2> /dev/null)
    printf '%s\n' "$top" | leaks_into "docker top"
    case $top in *KcAdmMain* | *kcadm.sh*) caught=$((caught + 1)) ;; esac
    stand_in_exec docker inspect c4-infra.keycloak 2> /dev/null | leaks_into "docker inspect"
    count=$((count + 1))
    echo "$count $caught" > "$work/keycloak.samples"
  done
}
sample_host &
samplers+=($!)
sample_keycloak &
samplers+=($!)
sleep 2

# .env rewritten by write-env.sh, as the workflow's runner does: the demo environment's secrets
# (here, the values of the stand-in's .env) with a new KC_REGISTRATION_CLIENT_SECRET
rewrite_env() {
  stand_in_exec -i sh -c 'cat > /tmp/write-env.sh' < demo/write-env.sh || return 1
  MSYS_NO_PATHCONV=1 docker exec -e NEXT_SECRET "$STAND_IN_NAME" bash -c '
    set -e
    cd "$1"
    value() { local line; line=$(grep -m1 "^$1=" .env); line=${line#*=}; printf "%s" "${line//\$\$/\$}"; }
    export INFRA_HOST=$(value INFRA_HOST) KC_IMAGE=$(value KC_IMAGE) PROXY_IMAGE=$(value PROXY_IMAGE) KC_ADMIN_USERNAME=$(value KC_BOOTSTRAP_ADMIN_USERNAME)
    export KC_ADMIN_PASSWORD=$(value KC_BOOTSTRAP_ADMIN_PASSWORD) KC_DB_PASSWORD=$(value KC_DB_PASSWORD)
    export RABBITMQ_ADMIN_PASSWORD=$(value RABBITMQ_ADMIN_PASSWORD) MAILPIT_SMTP_PASSWORD=$(value MAILPIT_SMTP_PASSWORD)
    export MAILPIT_UI_PASSWORD_HASH=$(value MAILPIT_UI_PASSWORD_HASH) GRAFANA_ADMIN_PASSWORD=$(value GRAFANA_ADMIN_PASSWORD)
    export KC_REGISTRATION_CLIENT_SECRET=$NEXT_SECRET
    bash /tmp/write-env.sh .env
    rm -f /tmp/write-env.sh
    sed -i "s/^COMPOSE_FILE=.*/&:compose.no-acme.yml/" .env' sh "$DIR"
}
check "AC-05: .env is rewritten by write-env.sh with a new secret" rewrite_env
holds_next_secret() { # compared in files: neither secret on a command line
  secret_into "$work/new-secret" || return 1
  printf '%s\n' "$NEXT_SECRET" > "$work/next-secret"
  cmp -s "$work/new-secret" "$work/next-secret" || { echo ".env doesn't hold the new secret"; return 1; }
}
check "AC-05: .env holds it" holds_next_secret
in_stack deploy-3.log bash ./demo/deploy.sh
check "AC-05: without KC_SETUP_ADMIN_*, deploy.sh fails" exited 1 deploy-3.log
check "AC-05: saying to set KC_SETUP_ADMIN_USERNAME and KC_SETUP_ADMIN_PASSWORD" \
  says deploy-3.log "set the KC_SETUP_ADMIN_USERNAME and KC_SETUP_ADMIN_PASSWORD secrets of the demo environment"
export KC_SETUP_ADMIN_USERNAME=ops KC_SETUP_ADMIN_PASSWORD=$OPS_PASSWORD
in_stack deploy-4.log bash ./demo/deploy.sh
unset KC_SETUP_ADMIN_USERNAME KC_SETUP_ADMIN_PASSWORD
check "AC-05: with KC_SETUP_ADMIN_* (ops), deploy.sh exits 0" exited 0 deploy-4.log
check "AC-05: it logs in as ops" says deploy-4.log "Logged in as ops (KC_SETUP_ADMIN_USERNAME)"
check "AC-05: and sets the account's secret to .env's" says deploy-4.log "Registration account $CLIENT: its secret set to .env's"
for i in 1 2 3; do
  in_stack "register-r$i.log" bash ./register-app.sh --app faito --realm "$APPS/faito-realm.json"
  check "AC-05: registration $i after the rotation works" exited 0 "register-r$i.log"
  check "AC-05: it finds realm faito" says "register-r$i.log" "Realm faito: already in Keycloak, left as it is"
done
login_with_old() {
  OLD_SECRET=$(cat "$work/old-secret") MSYS_NO_PATHCONV=1 docker exec -e OLD_SECRET "$STAND_IN_NAME" bash -c '
    KC_CLI_CLIENT_SECRET=$OLD_SECRET docker exec -e KC_CLI_CLIENT_SECRET c4-infra.keycloak sh -c "
      trap \"rm -f /dev/shm/c4-registration-old.kcadm\" EXIT
      /opt/keycloak/bin/kcadm.sh config credentials --config /dev/shm/c4-registration-old.kcadm \
        --server http://localhost:8080/auth --realm master --client $1"' sh "$CLIENT" < /dev/null
}
check "AC-05: a login with the former secret fails (Invalid client credentials)" \
  refused_with "Invalid client credentials" login_with_old

sleep 2
touch "$work/sample.stop"
wait "${samplers[@]}"
samplers=()
read -r host_samples host_caught < "$work/host.samples"
read -r kc_samples kc_caught < "$work/keycloak.samples"
check "AC-06: ps -eo args caught the registration at work ($host_caught of $host_samples samples)" test "${host_caught:-0}" -ge 1
check "AC-06: docker top caught the admin CLI at work ($kc_caught of $kc_samples samples)" test "${kc_caught:-0}" -ge 1
no_leak() {
  [ ! -s "$work/leaks" ] || { echo "a secret appears in:"; LC_ALL=C sort "$work/leaks" | uniq -c; return 1; }
}
check "AC-06: neither secret appears in ps -eo args, docker top nor docker inspect" no_leak
no_session_left() {
  local left
  left=$(stand_in_exec docker exec c4-infra.keycloak ls -A /dev/shm) || return 1
  ! grep -q c4-registration <<< "$left" || { echo "$left"; return 1; }
}
check "AC-06: no session is left in Keycloak's /dev/shm" no_session_left
finish
