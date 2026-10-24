#!/usr/bin/env bash
# 0006: the registration account on the workstation (AC-2 to AC-6).
#
#   AC-2  it may change neither the master realm nor a realm no registry entry assigns (403);
#   AC-3  a realm the bootstrap administrator created (verif-granted, made here, in the fixture
#         registry tests/fixtures/0006/registry-granted.txt): up.sh's ensure grants it, and the account
#         holds every role of verif-granted-realm; Faito's deploy-dev.sh (up.sh, then its
#         registration) finds realm faito, with no administrator;
#   AC-4  a realm it may not manage (verif-hidden, created by an administrator, in the fixture registry
#         tests/fixtures/0006/registry.txt but never granted): the registration exits 1, says so, and
#         changes nothing, with --reset-realms too;
#   AC-5  `registration-account.sh rotate`: a registration works with the new secret, a login with the
#         former one fails;
#   AC-6  while registrations (and a rotation) run, the secret is neither in the host's process list
#         (Windows': Win32_Process; elsewhere `ps -eo args`), nor in `docker top`, nor in
#         `docker inspect` of Keycloak; no session is left in its /dev/shm.
#
#   bash tests/0006-account.sh
#
# Needs the dev stack (up.sh) and Faito's repository (FAITO_DIR, default ../faito): its deploy-dev.sh
# and its realm export. Rotates the registration secret of .env (twice): the account keeps working.
# The fixture realms are removed whatever happens.
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/keycloak.sh

FAITO_DIR=${FAITO_DIR:-../faito}
FAITO_REALM=$FAITO_DIR/keycloak/import/faito-realm.json
FIXTURE=tests/fixtures/0006
CLIENT=$(_kc_env_value KC_REGISTRATION_CLIENT_ID)
ACCOUNT=service-account-$CLIENT

umask 077
work=$(mktemp -d)
samplers=()
# the applications whose network (0007: each registration makes sure of it) this test creates
new_networks=()
for app in verif-hidden faito; do
  docker network inspect "c4-infra.$app" > /dev/null 2>&1 || new_networks+=("$app")
done
remove_fixtures() {
  kc_admin delete realms/verif-unassigned > /dev/null 2>&1
  kc_admin delete realms/verif-granted > /dev/null 2>&1
  kc_admin delete realms/verif-hidden > /dev/null 2>&1
}
cleanup() {
  local app
  touch "$work/sample.stop"
  [ ${#samplers[@]} -eq 0 ] || wait "${samplers[@]}" 2> /dev/null
  remove_fixtures
  for app in "${new_networks[@]}"; do
    bash networks.sh remove "$app" > /dev/null
  done
  rm -rf "$work"
}
trap cleanup EXIT
remove_fixtures

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
# <log> <command…>: runs it, its output into $work/<log>, its exit status into $status
run() {
  local log=$1
  shift
  "$@" > "$work/$log" 2>&1 < /dev/null
  status=$?
}
exited() { # <expected status> <log>
  [ "$status" -eq "$1" ] || { echo "exit $status:"; tail -n 20 "$work/$2"; return 1; }
}
says() { # <log> <text>
  grep -qF -- "$2" "$work/$1" || { echo "output:"; tail -n 20 "$work/$1"; return 1; }
}
never_says() { # <log> <text>
  ! grep -qF -- "$2" "$work/$1" || { echo "output:"; tail -n 20 "$work/$1"; return 1; }
}
realm_field() { # <realm> <field>
  kc_admin get "realms/$1" --fields "$2" --format csv --noquotes 2> /dev/null | tr -d '\r'
}

check "Keycloak is healthy" kc_wait_healthy 60
check "Faito's repository is there ($FAITO_DIR)" test -f "$FAITO_DIR/deploy-dev.sh" -a -f "$FAITO_REALM"
check "the registration account is named in .env ($CLIENT)" test -n "$CLIENT"

# AC-2
check "AC-2: the account may not change the master realm (403)" \
  refused_with 403 kc_registration update realms/master -s displayName=x
check "an administrator creates realm verif-unassigned, which no registry entry assigns" \
  kc_admin create realms -s realm=verif-unassigned -s enabled=true
check "AC-2: the account may not change verif-unassigned (403)" \
  refused_with 403 kc_registration update realms/verif-unassigned -s displayName=x
check "AC-2: nor delete it (403)" refused_with 403 kc_registration delete realms/verif-unassigned
check "AC-2: verif-unassigned is still there" kc_admin get realms/verif-unassigned --fields realm
kc_admin delete realms/verif-unassigned > /dev/null 2>&1

# AC-3
granted() { # <realm>: every role of the master client <realm>-realm is the account's
  local direct available
  direct=$(kc_admin get-roles --uusername "$ACCOUNT" --cclientid "$1-realm" --fields name --format csv --noquotes 2> /dev/null | tr -d '\r')
  available=$(kc_admin get-roles --uusername "$ACCOUNT" --cclientid "$1-realm" --available --fields name --format csv --noquotes 2> /dev/null | tr -d '\r')
  grep -qx manage-realm <<< "$direct" && [ -z "$available" ] \
    || { echo "holds: $(echo $direct)"; echo "not granted: $(echo $available)"; return 1; }
}
# Its Given made here, whatever this workstation's history: a realm the bootstrap administrator
# created, which the account may not manage yet (verif-granted, tests/fixtures/0006/registry-granted.txt).
# Realm faito can't serve: Faito's registration creates it as the account on a Keycloak started
# since 0006 (0012 re-created this workstation's), and Keycloak gives a realm's creator every role
# of <realm>-realm but impersonation, which ensure leaves as it is (no administrator needed).
check "an administrator creates realm verif-granted, which the account may not manage yet" \
  kc_admin create realms -s realm=verif-granted -s enabled=true
run grant.log env REGISTRY_FILE="$PWD/$FIXTURE/registry-granted.txt" bash registration-account.sh ensure
check "AC-3: up.sh's ensure exits 0" exited 0 grant.log
check "AC-3: it grants realm verif-granted to the account" says grant.log "Registration account $CLIENT: realm verif-granted granted"
check "AC-3: the account holds every role of verif-granted-realm" granted verif-granted
kc_admin delete realms/verif-granted > /dev/null 2>&1
run deploy.log bash "$FAITO_DIR/deploy-dev.sh"
check "AC-3: Faito's deploy-dev.sh exits 0" exited 0 deploy.log
check "AC-3: its up.sh finds the account up to date" says deploy.log "Registration account $CLIENT: up to date"
check "AC-3: with no administrator" never_says deploy.log "Logged in as"
check "AC-3: its registration finds realm faito" says deploy.log "Realm faito: already in Keycloak, left as it is"

# AC-4
check "an administrator creates realm verif-hidden (displayName before), never granted to the account" \
  kc_admin create realms -s realm=verif-hidden -s enabled=true -s displayName=before
hidden_id=$(realm_field verif-hidden id)
register_hidden() { # <log> [--reset-realms]
  local log=$1
  shift
  run "$log" env REGISTRY_FILE="$PWD/$FIXTURE/registry.txt" \
    bash register-app.sh --app verif-hidden --realm "$FIXTURE/verif-hidden-realm.json" "$@"
}
for variant in "" --reset-realms; do
  register_hidden hidden.log $variant
  label="AC-4${variant:+ ($variant)}"
  check "$label: the registration of verif-hidden exits 1" exited 1 hidden.log
  check "$label: it says the account may not manage realm verif-hidden" \
    says hidden.log "Realm verif-hidden is in Keycloak, but the registration account $CLIENT may not manage it"
  check "$label: and that nothing was registered" says hidden.log "nothing was registered"
  check "$label: no deletion announced" never_says hidden.log "Deleting realm"
  check "$label: no import announced" never_says hidden.log "Importing realm"
  check "$label: verif-hidden is the same realm (its id)" test "$(realm_field verif-hidden id)" = "$hidden_id"
  check "$label: its displayName is still 'before'" test "$(realm_field verif-hidden displayName)" = before
done
kc_admin delete realms/verif-hidden > /dev/null 2>&1

# AC-5
old_secret=$(kc_secret_file) && mv "$old_secret" "$work/old-secret"
run rotate.log bash registration-account.sh rotate
check "AC-5: registration-account.sh rotate exits 0" exited 0 rotate.log
check "AC-5: it sets the account's secret to .env's new one" says rotate.log "Registration account $CLIENT: its secret set to .env's"
new_secret=$(kc_secret_file) && mv "$new_secret" "$work/new-secret"
check "AC-5: .env holds a new secret" bash -c '! cmp -s "$1" "$2"' sh "$work/old-secret" "$work/new-secret"
run after-rotate.log bash register-app.sh --app faito --realm "$FAITO_REALM"
check "AC-5: a registration works after the rotation" exited 0 after-rotate.log
check "AC-5: it finds realm faito" says after-rotate.log "Realm faito: already in Keycloak, left as it is"
login_with_old() {
  KC_CLI_CLIENT_SECRET=$(cat "$work/old-secret") MSYS_NO_PATHCONV=1 docker exec -e KC_CLI_CLIENT_SECRET "$KC_CONTAINER" sh -c '
    trap "rm -f /dev/shm/c4-registration-old-$$.kcadm" EXIT
    /opt/keycloak/bin/kcadm.sh config credentials --config /dev/shm/c4-registration-old-$$.kcadm \
      --server http://localhost:8080/auth --realm master --client "$1"' sh "$CLIENT" < /dev/null
}
check "AC-5: a login with the former secret fails (Invalid client credentials)" \
  refused_with "Invalid client credentials" login_with_old

# AC-6: the samplers, until $work/sample.stop exists. Each source is piped to leaks_into: grep -F -f
# reads it all (no -q: the source is never cut short) and prints nothing; a match is recorded by the
# source's name only, whatever the source's own exit status
cat "$work/new-secret" > "$work/secrets"
leaks_into() { # <source name>
  if grep -F -f "$work/secrets" > /dev/null; then echo "$1" >> "$work/leaks"; fi
}
sample_host() {
  local count=0 caught=0 list
  while [ ! -f "$work/sample.stop" ]; do
    if command -v powershell.exe > /dev/null; then
      list=$(powershell.exe -NoProfile -Command "Get-CimInstance Win32_Process | Select-Object -ExpandProperty CommandLine" 2> /dev/null)
    else
      list=$(ps -eo args)
    fi
    printf '%s\n' "$list" | leaks_into "the host's process list"
    case $list in *register-app.sh* | *registration-account.sh*) caught=$((caught + 1)) ;; esac
    count=$((count + 1))
    echo "$count $caught" > "$work/host.samples"
  done
}
sample_keycloak() {
  local count=0 caught=0 top
  while [ ! -f "$work/sample.stop" ]; do
    # docker top wants the PID column (-eo args alone: "Couldn't find PID field in ps output")
    top=$(docker top "$KC_CONTAINER" -eo pid,args 2> /dev/null)
    printf '%s\n' "$top" | leaks_into "docker top"
    case $top in *KcAdmMain* | *kcadm.sh*) caught=$((caught + 1)) ;; esac
    docker inspect "$KC_CONTAINER" 2> /dev/null | leaks_into "docker inspect"
    count=$((count + 1))
    echo "$count $caught" > "$work/keycloak.samples"
  done
}
# A rotation as the demo host's deployment does it: a new secret in .env, then ensure. Known before
# the sampling starts, so that both secrets are looked for throughout. .env is rewritten by builtins:
# the secret is on no command line.
next_secret=$(openssl rand -hex 32)
printf '%s\n' "$next_secret" >> "$work/secrets"
replace_secret() {
  local line
  {
    while IFS= read -r line || [ -n "$line" ]; do
      if [[ $line == KC_REGISTRATION_CLIENT_SECRET=* ]]; then
        printf '%s\n' "KC_REGISTRATION_CLIENT_SECRET=$next_secret"
      else
        printf '%s\n' "$line"
      fi
    done < .env
  } > "$work/env"
  cat "$work/env" > .env
  rm -f "$work/env"
}
# the detector's own check: the secrets, fed to it, are caught
leaks_into control < "$work/secrets"
check "AC-6: the detector catches the secret when it is there" grep -qx control "$work/leaks"
rm -f "$work/leaks"
sample_host &
samplers+=($!)
sample_keycloak &
samplers+=($!)
sleep 2
for i in 1 2 3 4 5; do
  run "register-$i.log" bash register-app.sh --app faito --realm "$FAITO_REALM"
  check "AC-6: registration $i works" exited 0 "register-$i.log"
done
replace_secret
run ensure-6.log bash registration-account.sh ensure
check "AC-6: a new secret in .env, then ensure, sets it in Keycloak" says ensure-6.log "Registration account $CLIENT: its secret set to .env's"
run register-6.log bash register-app.sh --app faito --realm "$FAITO_REALM"
check "AC-6: a registration with the new secret works" exited 0 register-6.log
sleep 2
touch "$work/sample.stop"
wait "${samplers[@]}"
samplers=()
read -r host_samples host_caught < "$work/host.samples"
read -r kc_samples kc_caught < "$work/keycloak.samples"
check "AC-6: the host's process list caught the registrations at work ($host_caught of $host_samples samples)" \
  test "${host_caught:-0}" -ge 1
check "AC-6: docker top caught the admin CLI at work ($kc_caught of $kc_samples samples)" test "${kc_caught:-0}" -ge 1
no_leak() {
  [ ! -s "$work/leaks" ] || { echo "the secret appears in:"; sort "$work/leaks" | uniq -c; return 1; }
}
check "AC-6: the secret appears in no process list nor in docker inspect" no_leak
check "AC-6: no session is left in Keycloak's /dev/shm" \
  bash -c '! MSYS_NO_PATHCONV=1 docker exec "$1" ls -A /dev/shm | grep -q c4-registration' sh "$KC_CONTAINER"
finish
