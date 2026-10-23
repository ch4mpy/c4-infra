#!/usr/bin/env bash
# 0002: on a stand-in demo host, one account per application (AC-1 to AC-4, AC-7, AC-8):
#
#   - the accounts as docs/demo-setup.md prepares them (stand_in_accounts: vps-bootstrap.sh c4-infra,
#     then app hururaa and app faito, keys generated inside the stand-in), the shared stack deployed
#     as c4-infra over ssh (demo/deploy.sh, which installs c4-app);
#   - Hurura'a's fixture (tests/fixtures/0002/hururaa/, its .env holding a marker) rsynced to
#     ~hururaa/hururaa/ and deployed with Hurura'a's key: sudo c4-app register, sudo c4-app up;
#   - AC-2, AC-8: with Faito's key, Faito deployed with docs/migration.md's own lines ("On the demo
#     host", read from the document; <project> and <realm> faito, $VPS the stand-in's address):
#     its rsync, sudo c4-app pull (without its GHCR login: no registry here), register and up
#     succeed: faito.gateway runs, the reverse proxy reaches it, its site belongs to c4-infra; and
#     docs/demo-setup.md's bootstrap commands are the ones stand_in_accounts runs;
#   - AC-3: the faito-realm.json of that registration, whose "realm" field says public-facing,
#     imports realm faito, and no public-facing realm appears; through sudo c4-app register,
#     Hurura'a's realm file with --reset-realms, Hurura'a's RabbitMQ user, a themes directory holding
#     tickee (keycloak/themes/tickee, placed beforehand, unchanged), the two hostile routes files, a
#     path outside ~/faito/, a symbolic link in it: each refused;
#   - AC-1: with Faito's key, reading Hurura'a's .env or the shared stack's, docker (directly or
#     through sudo), stopping Hurura'a's container, a compose file whose env_file is Hurura'a's .env,
#     and a connection to Hurura'a's container's address (the firewall's rule; c4-infra's account
#     connects): refused; sudo c4-app down stops Faito's project only;
#   - AC-4: the registration secret in no output of c4-app, the stack's .env mode 600 and c4-infra's,
#     sudo -l listing c4-app only;
#   - AC-7: c4-infra's account deploys the stack again (demo/deploy.sh); Faito's can neither enter
#     the stack's directory, nor restart it, nor install c4-app.
#
#   bash tests/0002-accounts.stand-in.sh      (bash tests/run.sh --all runs it)
#
# As tests/0003-demo-deploy.stand-in.sh: the Keycloak image is the one up.sh builds here, loaded
# into the stand-in; Let's Encrypt is kept out (tests/stand-in-host/compose.no-acme.yml). The
# applications' images are the stand-in's caddy (no registry login: `pull --registry` needs a real
# one). Passwords and markers travel on stdin, never on a command line.
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/stand-in-host.sh

FIXTURES=tests/fixtures/0002
STACK=/home/c4-infra/c4-infra
UPLOADS=/root/apps

umask 077
work=$(mktemp -d)
trap 'stand_in_down; rm -rf "$work"' EXIT

# <log> <account> <command>: over ssh as <account>, its output into $work/<log> (and $work/all.log,
# what AC-4 searches), its exit status into $status
as() {
  local log=$1
  stand_in_ssh "$2" "$3" > "$work/$log" 2>&1
  status=$?
  { echo "== $2: $3"; cat "$work/$log"; } >> "$work/all.log"
}
exited_0() { # <log>
  [ "$status" -eq 0 ] || { echo "exit $status:"; tail -n 25 "$work/$1"; return 1; }
}
refused() { # <log>
  [ "$status" -ne 0 ] || { echo "exited 0:"; tail -n 25 "$work/$1"; return 1; }
}
says() { # <log> <text>
  grep -qF -- "$2" "$work/$1" || { echo "output:"; tail -n 25 "$work/$1"; return 1; }
}
never_says_file() { # <log> <file holding the text>
  ! grep -qF -f "$2" "$work/$1" || { echo "the output holds it"; return 1; }
}
refused_saying() { # <label> <log> <text>
  check "$1: refused" refused "$2"
  check "$1: says \"$3\"" says "$2" "$3"
}
running() { # <container>
  [ "$(stand_in_exec docker inspect -f '{{.State.Running}}' "$1" 2> /dev/null | tr -d '\r')" = true ]
}
not_running() { # <container>
  ! running "$1"
}
in_stand_in() { # <command…>: as root in the stand-in, its output kept quiet
  stand_in_exec "$@" > /dev/null 2>&1
}

# AC-8: the lines of docs/migration.md's workflow ("On the demo host"), as the document writes them
doc_line() { # <extended regex>: the first line of docs/migration.md matching it, unindented
  grep -E "$1" docs/migration.md | head -n 1 | sed 's/\r$//; s/^[[:space:]]*//'
}
DOC_RSYNC=$(doc_line '^[[:space:]]*rsync .*"\$VPS:~/<project>/"$')
DOC_PULL=$(doc_line '^[[:space:]]*ssh "\$VPS" sudo c4-app pull ')
DOC_REGISTER=$(doc_line '^[[:space:]]*ssh "\$VPS" sudo c4-app register ')
DOC_UP=$(doc_line '^[[:space:]]*ssh "\$VPS" sudo c4-app up$')
# <log> <app> <line>: a line of the document, as its workflow runs it, in the stand-in from
# $UPLOADS/<app> (which holds deploy/, the runner's directory): <project> and <realm> are <app>, $VPS
# its account on the stand-in, ssh and rsync use its key; output and status as as()'s
doc_run() {
  local log=$1 app=$2 line=$3
  line=${line//<project>/$app}
  line=${line//<realm>/$app}
  stand_in_exec bash -c '
    cd "$1" || exit 1
    export VPS=$2@127.0.0.1 RSYNC_RSH=$3
    # the ssh binary with the key (command: not this function again)
    ssh() { command $RSYNC_RSH "$@"; }
    eval "$4"' sh "$UPLOADS/$app" "$app" "$(stand_in_ssh_command "$app")" "$line" > "$work/$log" 2>&1
  status=$?
  { echo "== $app, from docs/migration.md: $line"; cat "$work/$log"; } >> "$work/all.log"
}

# An application's files, from its fixture, into $UPLOADS/<app>/deploy/ (the workflow's runner's
# directory), its .env from <env file>; then docs/migration.md's rsync line sends them to ~<app>/<app>/
# with its key
upload() { # <app> <env file> [<extra fixture file or directory>, or <fixture file>:<name>…]
  local app=$1 env=$2 extra deploy=$UPLOADS/$1/deploy
  shift 2
  stand_in_exec rm -rf "$UPLOADS/$app"
  stand_in_exec mkdir -p "$deploy" || return 1
  (cd "$FIXTURES/$app" && tar -cf - .) | stand_in_exec -i tar -xf - --no-same-owner -C "$deploy" || return 1
  for extra in "$@"; do
    if [[ $extra == *:* ]]; then
      stand_in_exec -i sh -c 'cat > "$1"' sh "$deploy/${extra#*:}" < "$FIXTURES/${extra%%:*}" || return 1
    else
      (cd "$FIXTURES" && tar -cf - "$extra") | stand_in_exec -i tar -xf - --no-same-owner -C "$deploy" || return 1
    fi
  done
  stand_in_exec -i sh -c 'umask 077 && cat > "$1"' sh "$deploy/.env" < "$env" || return 1
  doc_run "upload-$app.log" "$app" "$DOC_RSYNC"
  [ "$status" -eq 0 ] || { cat "$work/upload-$app.log"; return 1; }
}

# Keycloak's admin CLI in the stand-in, as the bootstrap administrator of the stack's .env (read as
# data, its password in the environment)
kc_get() { # <path>
  stand_in_exec bash -c '
    value() { grep -m1 "^$1=" "$2/.env" | cut -d= -f2-; }
    KC_CLI_PASSWORD=$(value KC_BOOTSTRAP_ADMIN_PASSWORD "$1") docker exec -e KC_CLI_PASSWORD c4-infra.keycloak \
      /opt/keycloak/bin/kcadm.sh get "$2" --fields realm,displayName --no-config --server http://localhost:8080/auth \
      --realm master --user "$(value KC_BOOTSTRAP_ADMIN_USERNAME "$1")"' sh "$STACK" "$1" < /dev/null 2>&1
}
realm_absent() { # <realm>
  local output
  output=$(kc_get "realms/$1")
  [[ $output == *"Resource not found"* ]] || { echo "$output"; return 1; }
}

# AC-8: the documents' commands are the ones this test runs
check "AC-8: docs/migration.md gives the rsync line ($DOC_RSYNC)" test "$DOC_RSYNC" = 'rsync -az --delete deploy/ "$VPS:~/<project>/"'
check "AC-8: and the pull ($DOC_PULL)" \
  test "$DOC_PULL" = 'ssh "$VPS" sudo c4-app pull --registry ghcr.io --registry-user "$GHCR_USER" <<< "$GHCR_TOKEN"'
check "AC-8: the registration ($DOC_REGISTER)" test -n "$DOC_REGISTER"
check "AC-8: and the start ($DOC_UP)" test "$DOC_UP" = 'ssh "$VPS" sudo c4-app up'
check "AC-8: the workflow runs as <project>@" grep -qF 'VPS: <project>@${{ secrets.VPS_HOST }}' docs/migration.md
# what stand_in_accounts runs, as root: vps-bootstrap.sh c4-infra, then app <app>, with each key
check "AC-8: docs/demo-setup.md prepares the host with vps-bootstrap.sh c4-infra" \
  grep -qF "\"sudo bash /tmp/vps-bootstrap.sh c4-infra '\$(cat c4-infra-demo.pub)'\"" docs/demo-setup.md
check "AC-8: and adds an application with vps-bootstrap.sh app <app>" \
  grep -qF "\"sudo bash /tmp/vps-bootstrap.sh app <app> '\$(cat <app>-demo.pub)'\"" docs/demo-setup.md
check "AC-8: stand_in_accounts runs that script with those arguments" \
  grep -qF 'bash /tmp/vps-bootstrap.sh app "$app" "$(cat "$keys/$app.pub")"' tests/lib/stand-in-host.sh
check "AC-8: docs/demo-setup.md gives the application its host key secret" \
  grep -qF 'gh secret set VPS_KNOWN_HOSTS --env demo -R $A < c4-infra-demo.known_hosts' docs/demo-setup.md

check "the stand-in host starts" stand_in_up
check "the accounts (c4-infra, hururaa, faito), the shared stack deployed as c4-infra" stand_in_accounts hururaa faito
c4_app_mode=$(stand_in_exec stat -c '%U:%G %a' /usr/local/sbin/c4-app | tr -d '\r')
check "deploy.sh installed c4-app, root-owned ($c4_app_mode)" test "$c4_app_mode" = "root:root 755"

# Hurura'a, with its own key: its .env holds a marker that Faito must never read
printf 'HURURAA-MARKER-%s\n' "$(openssl rand -hex 12)" > "$work/marker"
printf 'HURURAA_SECRET=%s\n' "$(cat "$work/marker")" > "$work/hururaa.env"
check "Hurura'a's files are rsynced to ~hururaa/hururaa/ with its key" upload hururaa "$work/hururaa.env"
as hururaa-register.log hururaa "sudo c4-app register --proxy hururaa.routes"
check "Hurura'a registers (sudo c4-app register --proxy hururaa.routes)" exited_0 hururaa-register.log
as hururaa-up.log hururaa "sudo c4-app up"
check "Hurura'a starts (sudo c4-app up)" exited_0 hururaa-up.log
check "hururaa.gateway runs" running hururaa.gateway

# AC-2, AC-8: Faito's deployment with Faito's key, docs/migration.md's lines. Its faito-realm.json is
# the fixture whose "realm" field says public-facing (AC-3, below).
printf 'RABBITMQ_PASSWORD=%s\n' "$(openssl rand -hex 16)" > "$work/faito.env"
check "AC-2: Faito's files are rsynced to ~faito/faito/ with its key (the document's rsync line)" \
  upload faito "$work/faito.env" faito-realm-named-public-facing.json:faito-realm.json \
  public-facing-realm.json themes routes-hururaa-host.routes routes-keycloak-port.routes
# the pull without its GHCR login (the stand-in has no registry): the document's line up to it
doc_run pull.log faito "${DOC_PULL%% --registry*}"
check "AC-2: the document's sudo c4-app pull exits 0" exited_0 pull.log
doc_run register.log faito "$DOC_REGISTER"
check "AC-2: the document's sudo c4-app register (realm, routes file, RabbitMQ user) exits 0" exited_0 register.log
check "AC-2: it imports realm faito" says register.log "Importing realm faito"
check "AC-2: it installs Faito's site" says register.log "Reverse proxy: faito site installed (INFRA_ENV=demo)"
check "AC-2: and its RabbitMQ user" says register.log "RabbitMQ: virtual host faito, user faito-api"
doc_run up.log faito "$DOC_UP"
check "AC-2: the document's sudo c4-app up exits 0" exited_0 up.log
check "AC-2: faito.gateway runs" running faito.gateway
check "AC-2: the reverse proxy reaches it" \
  stand_in_exec sh -c 'docker exec c4-infra.reverse-proxy wget -qO- http://faito.gateway:7080/ | grep -qx faito.gateway'
site_owner=$(stand_in_exec stat -c %U "$STACK/caddy/apps/faito.caddy" 2>&1 | tr -d '\r')
check "AC-2: caddy/apps/faito.caddy exists, owned by c4-infra ($site_owner)" test "$site_owner" = c4-infra
check "AC-2: RabbitMQ has the user faito-api" \
  stand_in_exec sh -c 'docker exec c4-infra.rabbitmq rabbitmqctl -q list_users | grep -q "^faito-api"'
model_owner=$(stand_in_exec stat -c '%U:%G %a' /var/lib/c4-apps/.run.faito/model.json | tr -d '\r')
check "AC-2: the model root's compose ran is root's, in the root-only snapshot ($model_owner)" test "$model_owner" = "root:root 640"

# AC-3: that registration's faito-realm.json, whose "realm" field says public-facing, imported while
# realm faito didn't exist
realm_display() { kc_get realms/faito | grep -q '"displayName" : "faito-realm-named-public-facing (0002 fixture)"' || kc_get realms/faito; }
check "AC-3: realm faito is the file's (its displayName)" realm_display
check "AC-3: no public-facing realm appears" realm_absent public-facing

as reset.log faito "sudo c4-app register --realm public-facing-realm.json --reset-realms"
refused_saying "AC-3: Hurura'a's realm file, --reset-realms" reset.log "realm public-facing is not faito's"
check "AC-3: still no public-facing realm" realm_absent public-facing
as rabbit.log faito "sudo c4-app register --rabbitmq-user hururaa-api --rabbitmq-password-env RABBITMQ_PASSWORD"
refused_saying "AC-3: Hurura'a's RabbitMQ user" rabbit.log "--rabbitmq-user hururaa-api: not faito's RabbitMQ user"
check "AC-3: RabbitMQ has no user hururaa-api" \
  stand_in_exec sh -c '! docker exec c4-infra.rabbitmq rabbitmqctl -q list_users | grep -q "^hururaa-api"'
# Tickee's theme, installed beforehand in the stack's directory
stand_in_exec sh -c 'mkdir -p "$1/keycloak/themes/tickee/login" && echo "parent=base" > "$1/keycloak/themes/tickee/login/theme.properties" && chown -R c4-infra:c4-infra "$1/keycloak/themes/tickee"' sh "$STACK"
tickee_theme() { stand_in_exec sh -c 'cd "$1/keycloak/themes/tickee" && find . -type f | sort | xargs cksum | cksum' sh "$STACK" | tr -d '\r'; }
before=$(tickee_theme)
as themes.log faito "sudo c4-app register --themes themes"
refused_saying "AC-3: a themes directory holding tickee" themes.log "theme tickee is not faito's"
check "AC-3: keycloak/themes/tickee is as it was" test "$(tickee_theme)" = "$before"
as host.log faito "sudo c4-app register --proxy routes-hururaa-host.routes"
refused_saying "AC-3: a routes file serving hururaa.c4-soft.com" host.log "routes name neither a host nor a port"
as port.log faito "sudo c4-app register --proxy routes-keycloak-port.routes"
refused_saying "AC-3: a routes file routing to keycloak:8080" port.log "routes name neither a host nor a port: 'keycloak:8080'"
check "AC-3: Faito's site is still its own (faito.c4-soft.com)" \
  stand_in_exec grep -qxF 'faito.c4-soft.com {' "$STACK/caddy/apps/faito.caddy"
as outside.log faito "sudo c4-app register --proxy ../hururaa/x"
refused_saying "AC-3: a path outside ~/faito/ (../hururaa/x)" outside.log "../hururaa/x is outside ~/faito/: refused"
as absolute.log faito "sudo c4-app register --proxy /home/hururaa/hururaa/hururaa.routes"
refused_saying "AC-3: an absolute path" absolute.log "a path relative to ~/faito/ is expected"
as link.log faito "ln -s /home/c4-infra/c4-infra/.env ~/faito/leak && sudo c4-app register --proxy faito.routes"
refused_saying "AC-3: a symbolic link in ~/faito/" link.log "holds a symbolic link or a special file, refused: leak"
as unlink.log faito "rm ~/faito/leak"
as fifo.log faito "mkfifo ~/faito/pipe && sudo c4-app up"
refused_saying "a FIFO in ~/faito/" fifo.log "holds a symbolic link or a special file, refused: pipe"
as unfifo.log faito "rm ~/faito/pipe"
as app.log faito "sudo c4-app register --app hururaa --proxy faito.routes"
refused_saying "--app given" app.log "the application is the account's own (faito): no --app"

# AC-1: with Faito's key
as read-hururaa.log faito "cat /home/hururaa/hururaa/.env"
check "AC-1: reading Hurura'a's .env is refused" refused read-hururaa.log
check "AC-1: its marker isn't in the output" never_says_file read-hururaa.log "$work/marker"
as read-stack.log faito "cat $STACK/.env"
check "AC-1: reading the shared stack's .env is refused" refused read-stack.log
as staging.log faito "cat /var/lib/c4-apps/hururaa/.env"
check "AC-1: reading Hurura'a's staging copy is refused" refused staging.log
as ps.log faito "docker ps"
check "AC-1: docker ps is refused" refused ps.log
as stop.log faito "docker stop hururaa.gateway"
check "AC-1: docker stop hururaa.gateway is refused" refused stop.log
as sudo-docker.log faito "sudo -n docker ps"
check "AC-1: sudo -n docker ps is refused" refused sudo-docker.log
check "AC-1: hururaa.gateway still runs" running hururaa.gateway
# another application's env_file: compose reads the model as faito, which can't read it
sed '/container_name: faito.gateway/a\    env_file: [/home/hururaa/hururaa/.env]' "$FIXTURES/faito/compose.yml" > "$work/steal.yml"
check "a compose.yml whose env_file is Hurura'a's .env (fixture changed here)" grep -qF /home/hururaa/hururaa/.env "$work/steal.yml"
check "Faito sends it" stand_in_ssh -i faito 'cat > ~/faito/compose.yml' < "$work/steal.yml"
as steal.log faito "sudo c4-app up"
check "AC-1: sudo c4-app up with it is refused" refused steal.log
check "AC-1: the marker is in no output" never_says_file steal.log "$work/marker"
marker_not_in_staging() { ! stand_in_exec -i grep -rqF -f /dev/stdin /var/lib/c4-apps/faito < "$work/marker"; }
check "AC-1: nor in Faito's staging copy" marker_not_in_staging
check "Faito's compose.yml is restored" stand_in_ssh -i faito 'cat > ~/faito/compose.yml' < "$FIXTURES/faito/compose.yml"
# the containers' addresses: the firewall's rule for c4-apps (c4-infra's account, outside it, connects)
hururaa_ip=$(stand_in_exec docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' hururaa.gateway | tr -d '\r')
check "hururaa.gateway has an address ($hururaa_ip)" test -n "$hururaa_ip"
as curl-c4-infra.log c4-infra "curl -s --max-time 3 http://$hururaa_ip:7080/"
check "control: c4-infra's account reaches http://$hururaa_ip:7080/" says curl-c4-infra.log hururaa.gateway
as curl-faito.log faito "curl -s --max-time 3 http://$hururaa_ip:7080/"
check "AC-1: Faito's account doesn't (the firewall's rule)" refused curl-faito.log
check "AC-1: nothing of Hurura'a's answer" bash -c '! grep -q hururaa.gateway "$1"' sh "$work/curl-faito.log"
as down.log faito "sudo c4-app down"
check "AC-1: sudo c4-app down exits 0" exited_0 down.log
check "AC-1: it stops faito.gateway" not_running faito.gateway
check "AC-1: and faito.frontend" not_running faito.frontend
check "AC-1: but not hururaa.gateway" running hururaa.gateway
check "AC-1: nor the shared stack's Keycloak" running c4-infra.keycloak
as up-again.log faito "sudo c4-app up"
check "Faito starts again" exited_0 up-again.log
# the registry token on stdin, in a temporary configuration: a failed login leaves nothing behind
tmp_before=$(stand_in_exec ls -A /tmp | tr -d '\r')
as login.log faito "sudo c4-app pull --registry 127.0.0.1:5999 --registry-user verif <<< not-a-token"
check "a login to an unreachable registry fails" refused login.log
check "it leaves no temporary configuration in /tmp" test "$(stand_in_exec ls -A /tmp | tr -d '\r')" = "$tmp_before"
check "root's ~/.docker holds no credential for it" stand_in_exec sh -c '! grep -qs 127.0.0.1:5999 /root/.docker/config.json'

# AC-4
stand_in_exec sh -c 'grep -m1 "^KC_REGISTRATION_CLIENT_SECRET=" "$1/.env" | cut -d= -f2-' sh "$STACK" | tr -d '\r' > "$work/secret"
check "AC-4: the registration secret is read here (for the search)" test -s "$work/secret"
check "AC-4: the search catches it when it is there" grep -qF -f "$work/secret" "$work/secret"
check "AC-4: it is in no output of the accounts' commands (c4-app's included)" never_says_file all.log "$work/secret"
env_mode=$(stand_in_exec stat -c '%a %U' "$STACK/.env" | tr -d '\r')
check "AC-4: the stack's .env is mode 600, c4-infra's ($env_mode)" test "$env_mode" = "600 c4-infra"
as sudo-l.log faito "sudo -l"
only_c4_app() {
  local rules
  rules=$(sed -n '/may run the following commands/,$p' "$work/sudo-l.log" | tail -n +2 | sed '/^[[:space:]]*$/d')
  [ "$(printf '%s\n' "$rules" | tr -d '\r')" = "    (root) NOPASSWD: /usr/local/sbin/c4-app" ] || { cat "$work/sudo-l.log"; return 1; }
}
check "AC-4: sudo -l lists c4-app only" only_c4_app

# AC-7: the shared stack's account deploys; an application's can't
as deploy.log c4-infra "cd ~/c4-infra && bash ./demo/deploy.sh < /dev/null"
check "AC-7: as c4-infra, demo/deploy.sh exits 0" exited_0 deploy.log
as compose-ps.log c4-infra "cd ~/c4-infra && docker compose ps --format '{{.Name}} {{.Health}}'"
check "AC-7: and every service of the stack is healthy (6)" \
  bash -c '[ "$(grep -c " healthy" "$1")" -eq 6 ] || { cat "$1"; exit 1; }' sh "$work/compose-ps.log"
as cd.log faito "cd $STACK"
check "AC-7: as faito, cd $STACK is refused" refused cd.log
as restart.log faito "docker compose -p c4-infra restart"
check "AC-7: docker compose -p c4-infra restart is refused" refused restart.log
as install.log faito "sudo -n /usr/bin/install -o root -g root -m 0755 $STACK/demo/c4-app /usr/local/sbin/c4-app"
check "AC-7: sudo -n /usr/bin/install … /usr/local/sbin/c4-app is refused" refused install.log
as install-own.log faito "printf '#!/bin/sh\nid\n' > ~/c4-app && sudo -n /usr/bin/install -o root -g root -m 0755 /home/faito/c4-app /usr/local/sbin/c4-app"
check "AC-7: nor with a file of its own" refused install-own.log
check "AC-7: c4-app is still the deployed one" stand_in_exec cmp /usr/local/sbin/c4-app "$STACK/demo/c4-app"
check "AC-7: the stack's Keycloak still runs" running c4-infra.keycloak

# Review round 1 (2026-10-22): the RabbitMQ password c4-app registers is the value compose gives
# the containers from ~/faito/.env: written ab$$cd… with a comment after it, it is ab$cd…
raw="ab\$\$cd-$(openssl rand -hex 8)"
printf 'RABBITMQ_PASSWORD=%s # the demo broker\n' "$raw" > "$work/faito-dollar.env"
printf '%s\n' "${raw//\$\$/\$}" > "$work/faito-dollar.password"
check "Faito's .env, its password written ab\$\$cd… with a comment after it, is sent" \
  stand_in_ssh -i faito "cat > ~/faito/.env" < "$work/faito-dollar.env"
as dollar.log faito "sudo c4-app register --rabbitmq-user faito-api --rabbitmq-password-env RABBITMQ_PASSWORD"
check "sudo c4-app register --rabbitmq-user faito-api exits 0" exited_0 dollar.log
# the password reaches rabbitmqctl's stdin from a file of the stand-in (mode 600), within the stand-in:
# on no command line, and with an end of input (two nested `docker exec -i` from Windows lose it, and
# rabbitmqctl then waits); timeout bounds the call whatever happens
check "the expected password is written to a file of the stand-in (mode 600, on stdin)" \
  stand_in_exec -i sh -c 'umask 077 && cat > /root/faito-dollar.password' < "$work/faito-dollar.password"
check "RabbitMQ authenticates faito-api with ab\$cd… (compose's value, on stdin)" \
  stand_in_exec sh -c 'timeout 30 docker exec -i c4-infra.rabbitmq rabbitmqctl -q authenticate_user faito-api < /root/faito-dollar.password'
stand_in_exec rm -f /root/faito-dollar.password
finish
