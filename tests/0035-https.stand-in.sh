#!/usr/bin/env bash
# 0035: the stand-in demo host serves each registered site over HTTPS, from a local authority a test
# trusts in its own client alone (tests/lib/stand-in-host.sh: stand_in_ca_cert, stand_in_https):
#
#   - RQ-03: with no stack, then with a Caddy that has no local authority, both functions exit 1,
#     saying why; then, a proxy holding a root while the stand-in's 443 accepts connections and never
#     answers, stand_in_https returns non-zero within 45 s instead of waiting without end (intent 0047);
#   - AC-01: Faito's fixture registered and started with sudo c4-app: https://faito.c4-soft.com/fr/
#     answers 200 from faito.frontend, curl verifying against the root alone (its CAfile the root,
#     its CApath an empty directory), and the stand-in's own store refuses the site (curl exits 60);
#   - AC-02: Keycloak's discovery on https://infra.c4-soft.com answers, its issuer on https;
#   - AC-03: the stack redeployed as the workflow does, twice, its Caddyfile and env/demo.caddy
#     replaced (rsync) each time; the second deployment keeps the proxy's container (the first may
#     recreate it, Faito's network joined), so its mounts see the files replaced, as a deployment
#     that changes only caddy/ does; then Hurura'a's fixture registered: the root is the same, both
#     sites answer;
#   - AC-06: the checkout unchanged, no private key in the test's files or the uploads, the root in no
#     trust store of the stand-in or of its containers, no stand_in_https directory left.
#
#   bash tests/0035-https.stand-in.sh      (bash tests/run.sh --all runs it)
#
# As tests/0002-accounts.stand-in.sh: the Keycloak and proxy images are this machine's, loaded into the
# stand-in, and the applications' images its caddy.
#
# covers: tests/stand-in-host/ caddy/ compose.yml compose.demo.yml demo/ register-app.sh registry.sh
# covers: registry.txt routes.sh networks.sh registration-account.sh reverse-proxy/ keycloak/
# covers: keycloak-import/ tlds-alpha-by-domain.txt tests/fixtures/0002/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/stand-in-host.sh

FIXTURES=tests/fixtures/0002
UPLOADS=/root/apps-0035
UPLOAD=/root/c4-infra-upload

umask 077
work=$(mktemp -d)
trap 'stand_in_down; rm -rf "$work"' EXIT
checkout_before=$(git status --porcelain --untracked-files=all)

fails_saying() { # <text> <command…>: the command exits 1, saying the text
  local output status
  output=$("${@:2}" 2>&1)
  status=$?
  [ "$status" -eq 1 ] && grep -qF -- "$1" <<< "$output" || { echo "exit $status:"; printf '%s\n' "$output"; return 1; }
}
deploy_app() { # <app>: its fixture and a .env rsynced to ~<app>/<app>/ with its key, then sudo c4-app register --proxy <app>.routes and up
  local app=$1
  stand_in_exec rm -rf "$UPLOADS/$app"
  stand_in_exec mkdir -p "$UPLOADS/$app" || return 1
  (cd "$FIXTURES/$app" && tar -cf - .) | stand_in_exec -i tar -xf - --no-same-owner -C "$UPLOADS/$app" || return 1
  printf 'MARKER=0035\n' | stand_in_exec -i sh -c 'umask 077 && cat > "$1/.env"' sh "$UPLOADS/$app" || return 1
  stand_in_exec bash -c 'cd "$1" && rsync -az --delete -e "$2" ./ "$3@127.0.0.1:~/$3/"' \
    sh "$UPLOADS/$app" "$(stand_in_ssh_command "$app")" "$app" || return 1
  stand_in_ssh "$app" "sudo c4-app register --proxy $app.routes" > "$work/$app-register.log" 2>&1 \
    || { tail -n 20 "$work/$app-register.log"; return 1; }
  stand_in_ssh "$app" "sudo c4-app up" > "$work/$app-up.log" 2>&1 || { tail -n 20 "$work/$app-up.log"; return 1; }
}
redeploy_stack() { # the upload rsynced again as c4-infra, as stand_in_accounts does, then demo/deploy.sh
  stand_in_exec bash -c 'cd "$1" && rsync -az -e "$2" ./ c4-infra@127.0.0.1:~/c4-infra/' \
    sh "$UPLOAD" "$(stand_in_ssh_command c4-infra)" || return 1
  stand_in_ssh c4-infra "cd ~/c4-infra && bash ./demo/deploy.sh < /dev/null > ~/deploy-0035.log 2>&1" \
    || { stand_in_exec tail -n 30 /home/c4-infra/deploy-0035.log; return 1; }
}
answers() { # <host> <path> <body>: through stand_in_https, 200 and the body
  local output
  output=$(stand_in_https "$1" "$2" -w ' http=%{http_code}' 2>&1 | tr -d '\r')
  [[ $output == *"$3"*" http=200" ]] || { echo "output:"; printf '%s\n' "$output" | tail -n 5; return 1; }
}
one_certificate() { # <PEM>: one certificate openssl reads, no private key
  [ "$(grep -c 'BEGIN CERTIFICATE' <<< "$1")" -eq 1 ] && ! grep -q 'PRIVATE KEY' <<< "$1" \
    && openssl x509 -noout -subject <<< "$1" > /dev/null || { printf '%s\n' "$1"; return 1; }
}
verbose_says() { # <text>: stand_in_https -v's lines on Faito's page hold the text (a grep pattern)
  grep -q -- "$1" "$work/verbose.log" || { grep -E 'CAfile|CApath|verify' "$work/verbose.log"; return 1; }
}
system_store_refuses() { # the stand-in's curl, with the system's store only: exit 60
  local status
  stand_in_exec curl -s -o /dev/null --connect-to ::127.0.0.1: https://faito.c4-soft.com/fr/
  status=$?
  [ "$status" -eq 60 ] || { echo "curl exited $status"; return 1; }
}
issuer_is() { # <issuer>: Keycloak's discovery document, through stand_in_https: 200, that issuer
  local output
  output=$(stand_in_https infra.c4-soft.com /auth/realms/master/.well-known/openid-configuration \
    -w ' http=%{http_code}' 2>&1 | tr -d '\r')
  [[ $output == *" http=200" ]] && [ "$(jq -r .issuer <<< "${output% http=200}")" = "$1" ] \
    || { printf '%s\n' "$output" | head -c 400; return 1; }
}
no_private_key() { # in the test's files, the stack's upload and directory, the applications' uploads and directories
  local found
  found=$(grep -rlE 'BEGIN [A-Z ]*PRIVATE KEY' "$work"; stand_in_exec sh -c \
    'grep -rlE "BEGIN [A-Z ]*PRIVATE KEY" "$@" 2> /dev/null' sh "$UPLOAD" /home/c4-infra/c4-infra \
    "$UPLOADS" /home/faito/faito /home/hururaa/hururaa)
  [ -z "$found" ] || { echo "private keys in:"; printf '%s\n' "$found"; return 1; }
}
inodes() { # the inodes of the stack's Caddyfile and env/demo.caddy, on one line
  stand_in_exec stat -c %i /home/c4-infra/c4-infra/caddy/Caddyfile /home/c4-infra/c4-infra/caddy/env/demo.caddy \
    | tr -d '\r' | tr '\n' ' '
}
replaced() { # <inodes before>: both files have new inodes
  local now a b c d
  now=$(inodes) || return 1
  read -r a b <<< "$1"
  read -r c d <<< "$now"
  [ -n "$b" ] && [ -n "$d" ] && [ "$a" != "$c" ] && [ "$b" != "$d" ] || { echo "before: $1, after: $now"; return 1; }
}
proxy_container() { # the proxy's container id and start
  stand_in_exec docker inspect -f '{{.Id}} {{.State.StartedAt}}' c4-infra.reverse-proxy | tr -d '\r'
}
redeployed_keeping_proxy() { # redeploy_stack, the proxy's container the same before and after
  local before after
  before=$(proxy_container) && redeploy_stack && after=$(proxy_container) || return 1
  [ -n "$before" ] && [ "$after" = "$before" ] || { echo "before: $before, after: $after"; return 1; }
}
same_root() { # stand_in_ca_cert gives the root kept, which isn't empty
  local now
  now=$(stand_in_ca_cert) && [ -n "$root" ] && [ "$now" = "$root" ] || { echo "kept: ${root:0:80}"; echo "now: ${now:0:80}"; return 1; }
}
trusted_nowhere() { # <line of the root's body>: in no trust store of the stand-in, of the proxy, of a container with a shell
  local trusting
  [ -n "$1" ] || { echo "no root to look for"; return 1; }
  stand_in_exec docker exec c4-infra.reverse-proxy true || { echo "the proxy runs no shell command"; return 1; }
  trusting=$(stand_in_exec sh -c '
    stores="/etc/ssl/certs/ca-certificates.crt /usr/local/share/ca-certificates"
    grep -rqF "$1" $stores 2> /dev/null && echo "the stand-in"
    for container in $(docker ps --format "{{.Names}}"); do
      docker exec "$container" sh -c "grep -rqF \"\$0\" $stores" "$1" 2> /dev/null && echo "$container"
    done' sh "$1")
  [ -z "$trusting" ] || { echo "trusted by:"; printf '%s\n' "$trusting"; return 1; }
}

check "the stand-in host starts" stand_in_up

# RQ-03
check "RQ-03, no stack: stand_in_ca_cert fails, naming the missing proxy" \
  fails_saying "stand_in_ca_cert: the stand-in runs no c4-infra.reverse-proxy" stand_in_ca_cert
check "RQ-03, no stack: stand_in_https too" \
  fails_saying "stand_in_https: the stand-in runs no c4-infra.reverse-proxy" stand_in_https faito.c4-soft.com /fr/
check "the proxy's image is loaded" stand_in_load_image c4-infra/reverse-proxy
check "a Caddy without local authority starts (its image's own Caddyfile)" \
  stand_in_exec docker run -d --name c4-infra.reverse-proxy c4-infra/reverse-proxy
check "RQ-03, a Caddy without local authority: stand_in_ca_cert fails, saying so" \
  fails_saying "stand_in_ca_cert: the stand-in's Caddy has no local authority" stand_in_ca_cert
check "RQ-03, a Caddy without local authority: stand_in_https too" \
  fails_saying "stand_in_https: the stand-in's Caddy has no local authority" stand_in_https faito.c4-soft.com /fr/
stand_in_exec docker rm -f -v c4-infra.reverse-proxy > /dev/null

# a root to read (any certificate), and on the stand-in's 443 a listener that accepts and never answers
stall_bounded() {
  local listener pid start status elapsed
  stand_in_exec docker run -d --name c4-infra.reverse-proxy c4-infra/reverse-proxy sh -c \
    'mkdir -p /data/caddy/pki/authorities/local && cp /etc/ssl/certs/ca-certificates.crt /data/caddy/pki/authorities/local/root.crt && exec sleep 600' \
    > /dev/null || return 1
  listener=$(stand_in_exec -i sh -s <<'EOF'
setsid perl -MIO::Socket::INET -e '
  my $s = IO::Socket::INET->new(LocalAddr => "127.0.0.1", LocalPort => 443, Listen => 5, ReuseAddr => 1) or die "$!";
  my @held; while (my $c = $s->accept) { push @held, $c }' < /dev/null > /dev/null 2>&1 &
echo $!
EOF
)
  start=$SECONDS
  stand_in_https faito.c4-soft.com /fr/ > /dev/null 2>&1 &
  pid=$!
  while kill -0 "$pid" 2> /dev/null && [ $((SECONDS - start)) -lt 60 ]; do sleep 1; done
  if kill -0 "$pid" 2> /dev/null; then
    kill "$pid"
    status="did not return within 60 s"
  else
    wait "$pid"
    status=$?
  fi
  elapsed=$((SECONDS - start))
  stand_in_exec kill "${listener%$'\r'}" 2> /dev/null
  stand_in_exec docker rm -f -v c4-infra.reverse-proxy > /dev/null
  # 28, the stall's own status: another (7, 1) would mean the listener or the root never was there
  [ "$status" = 28 ] && [ "$elapsed" -le 45 ] || { echo "$status after $elapsed s"; return 1; }
}
check "0047 RQ-04: a site that accepts and never answers ends stand_in_https's wait within 45 s, status 28" stall_bounded

# AC-01
check "the applications' image is loaded" stand_in_load_image "$STAND_IN_CADDY_IMAGE"
check "the accounts (c4-infra, faito, hururaa), the shared stack deployed as c4-infra" stand_in_accounts faito hururaa
check "Faito's fixture registers and starts (sudo c4-app)" deploy_app faito
root=$(stand_in_ca_cert)
check "AC-01: stand_in_ca_cert gives one certificate, no key" one_certificate "$root"
check "AC-01: https://faito.c4-soft.com/fr/ answers 200 from faito.frontend" answers faito.c4-soft.com /fr/ faito.frontend
stand_in_https faito.c4-soft.com /fr/ -v -o /dev/null > "$work/verbose.log" 2>&1
check "AC-01: curl's CAfile is the root's copy" verbose_says 'CAfile: /tmp/stand_in_https.*/root.crt'
check "AC-01: its CApath an empty directory" verbose_says 'CApath: /tmp/stand_in_https.*/capath'
check "AC-01: it verified the certificate" verbose_says 'SSL certificate verify ok'
check "AC-01: the stand-in's own store refuses the site (curl exits 60)" system_store_refuses

# AC-02
check "AC-02: Keycloak's issuer is https://infra.c4-soft.com/auth/realms/master" \
  issuer_is https://infra.c4-soft.com/auth/realms/master

# AC-03
before=$(inodes)
stand_in_exec touch "$UPLOAD/caddy/Caddyfile" "$UPLOAD/caddy/env/demo.caddy"
check "AC-03: the stack is redeployed" redeploy_stack
check "AC-03: its Caddyfile and env/demo.caddy were replaced (new inodes)" replaced "$before"
before=$(inodes)
stand_in_exec touch "$UPLOAD/caddy/Caddyfile" "$UPLOAD/caddy/env/demo.caddy"
check "AC-03: redeployed again, the proxy's container kept" redeployed_keeping_proxy
check "AC-03: its Caddyfile and env/demo.caddy were replaced again" replaced "$before"
check "AC-03: Hurura'a's fixture registers and starts" deploy_app hururaa
check "AC-03: the root is the same" same_root
check "AC-03: https://hururaa.c4-soft.com/gateway/ answers 200 from hururaa.gateway" \
  answers hururaa.c4-soft.com /gateway/ hururaa.gateway
check "AC-03: https://faito.c4-soft.com/fr/ still answers" answers faito.c4-soft.com /fr/ faito.frontend

# AC-06
check "AC-06: the checkout is unchanged" test "$(git status --porcelain --untracked-files=all)" = "$checkout_before"
check "AC-06: no private key in the test's files or the uploads" no_private_key
check "AC-06: the root in no trust store" trusted_nowhere "$(sed -n 2p <<< "$root")"
check "AC-06: no stand_in_https directory left" test -z "$(stand_in_exec sh -c 'ls -d /tmp/stand_in_https.* 2> /dev/null')"
finish
