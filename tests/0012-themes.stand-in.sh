#!/usr/bin/env bash
# 0012: on a stand-in demo host (REQ-1 to REQ-3, REQ-6):
#
#   - AC-7: on the fresh stand-in, the master realm is created by the one-shot keycloak-import, and
#     the running Keycloak's environment holds neither the master realm administrator's password
#     nor Mailpit's SMTP password (neither their variables nor their values);
#   - AC-4: Tickee's account sends a theme tickee whose theme.properties holds
#     ${env.KC_DB_PASSWORD}: sudo c4-app register --themes refuses it, naming the file and its line;
#     nothing is installed, Keycloak isn't restarted;
#   - AC-3: as root, register-app.sh (what c4-app runs) refuses a theme holding a link to
#     /proc/self/environ among its resources, and a theme directory that is itself a link (c4-app
#     refuses links in what an application sends: these reach register-app.sh only from elsewhere).
#
#   bash tests/0012-themes.stand-in.sh      (bash tests/run.sh --all runs it)
#
# As tests/0002-accounts.stand-in.sh: the Keycloak image is the one up.sh builds here, loaded into
# the stand-in; Let's Encrypt is kept out (tests/stand-in-host/compose.no-acme.yml).
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/stand-in-host.sh

STACK=/home/c4-infra/c4-infra
UPLOADS=/root/apps-0012
INSTALLED=$STACK/keycloak/themes/tickee

umask 077
work=$(mktemp -d)
trap 'stand_in_down; rm -rf "$work"' EXIT

as() { # <log> <account> <command>: over ssh as <account>, its output into $work/<log>, sets status
  stand_in_ssh "$2" "$3" > "$work/$1" 2>&1
  status=$?
}
as_root() { # <log> <command…>: as root in the stand-in, its output into $work/<log>, sets status
  local log=$1
  shift
  stand_in_exec "$@" > "$work/$log" 2>&1 < /dev/null
  status=$?
}
refused() { # <log>
  [ "$status" -ne 0 ] || { echo "exited 0:"; tail -n 25 "$work/$1"; return 1; }
}
says() { # <log> <text>
  grep -qF -- "$2" "$work/$1" || { echo "output:"; tail -n 25 "$work/$1"; return 1; }
}
not_installed() {
  ! stand_in_exec test -e "$INSTALLED" || { echo "$INSTALLED is installed"; return 1; }
}
started_at() {
  stand_in_exec docker inspect -f '{{.State.StartedAt}}' c4-infra.keycloak | tr -d '\r'
}

check "the stand-in host starts" stand_in_up
check "the accounts (c4-infra, tickee), the shared stack deployed as c4-infra" stand_in_accounts tickee

# AC-7
imported_by_keycloak_import() {
  stand_in_exec docker logs c4-infra.keycloak-import 2>&1 | grep -qF "Realm 'master' imported" \
    || { echo "keycloak-import's log:"; stand_in_exec docker logs c4-infra.keycloak-import 2>&1 | tail -n 10; return 1; }
}
check "AC-7: the master realm was imported by keycloak-import" imported_by_keycloak_import
# Inside the stand-in: each password's variable and value, against the running Keycloak's environment
keycloak_env_lacks_secrets() {
  stand_in_exec -i bash -s "$STACK" <<'SCRIPT'
set -uo pipefail
environment=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' c4-infra.keycloak) || exit 1
problems=0
for variable in C4_MASTER_ADMIN_PASSWORD MAILPIT_SMTP_PASSWORD; do
  if grep -q "^$variable=" <<< "$environment"; then
    echo "c4-infra.keycloak's environment holds $variable"
    problems=1
  fi
done
for key in KC_BOOTSTRAP_ADMIN_PASSWORD MAILPIT_SMTP_PASSWORD; do
  value=$(grep "^$key=" "$1/.env" | tail -n 1 | cut -d= -f2- | sed "s/^'//; s/'\$//")
  [ -n "$value" ] || { echo "no $key in $1/.env"; problems=1; continue; }
  if grep -qF -- "$value" <<< "$environment"; then
    echo "c4-infra.keycloak's environment holds the value of .env's $key"
    problems=1
  fi
done
exit "$problems"
SCRIPT
}
check "AC-7: Keycloak's environment holds neither password (variables nor values)" keycloak_env_lacks_secrets

# AC-4: through sudo c4-app register, as Tickee
before=$(started_at)
send_tickee() {
  stand_in_exec rm -rf "$UPLOADS/tickee" || return 1
  stand_in_exec mkdir -p "$UPLOADS/tickee/themes/tickee/login" || return 1
  printf 'parent=keycloak\nkcHtmlClass=login-pf ${env.KC_DB_PASSWORD}\n' \
    | stand_in_exec -i sh -c 'cat > "$1"' sh "$UPLOADS/tickee/themes/tickee/login/theme.properties" || return 1
  stand_in_exec bash -c 'cd "$1" && rsync -az --delete -e "$2" ./ "$3@127.0.0.1:~/$3/"' \
    sh "$UPLOADS/tickee" "$(stand_in_ssh_command tickee)" tickee
}
check "AC-4: Tickee's files are rsynced to ~tickee/tickee/ with its key" send_tickee
as tickee-register.log tickee "sudo c4-app register --themes themes"
check "AC-4: sudo c4-app register refuses the theme" refused tickee-register.log
check "AC-4: naming tickee/login/theme.properties:2" says tickee-register.log "tickee/login/theme.properties:2: "
check "AC-4: nothing was registered" says tickee-register.log "nothing was registered"
check "AC-4: the theme isn't installed" not_installed
check "AC-4: Keycloak isn't restarted (started at $before)" test "$(started_at)" = "$before"

# AC-3: links, through register-app.sh as root
register_as_root() { # <log> <themes directory>
  as_root "$1" bash -c 'cd "$1" && bash ./register-app.sh --app tickee --themes "$2"' sh "$STACK" "$2"
}
as_root links.log bash -c 'rm -rf /root/0012 && mkdir -p /root/0012/leak/tickee/login/resources /root/0012/real/tickee/login /root/0012/dirlink \
  && printf "parent=keycloak\n" > /root/0012/leak/tickee/login/theme.properties \
  && printf "parent=keycloak\n" > /root/0012/real/tickee/login/theme.properties \
  && ln -s /proc/self/environ /root/0012/leak/tickee/login/resources/leak.txt \
  && ln -s /root/0012/real/tickee /root/0012/dirlink/tickee'
check "AC-3: the linked themes are made in the stand-in" test "$status" -eq 0
register_as_root leak.log /root/0012/leak
check "AC-3: a link to /proc/self/environ in a theme's resources: refused" refused leak.log
check "AC-3: naming tickee/login/resources/leak.txt" says leak.log "tickee/login/resources/leak.txt"
check "AC-3: as a symbolic link" says leak.log "symbolic link"
check "AC-3: nothing was registered" says leak.log "nothing was registered"
check "AC-3: the theme isn't installed" not_installed
register_as_root dirlink.log /root/0012/dirlink
check "AC-3: a theme directory that is a link: refused" refused dirlink.log
check "AC-3: as a symbolic link" says dirlink.log "symbolic link"
check "AC-3: nothing was registered" says dirlink.log "nothing was registered"
check "AC-3: the theme isn't installed" not_installed
check "AC-3: Keycloak isn't restarted (started at $before)" test "$(started_at)" = "$before"

finish
