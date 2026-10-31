#!/usr/bin/env bash
# 0048: the landing page and the demo accounts on a stand-in demo host, Faito's fixture (its realm with
# two users in two groups, its accounts file) registered with sudo c4-app:
#
#   - AC-07: sudo c4-app accounts, as faito, prints each account with a password of 24 characters at
#     least (lowercase, uppercase, digit, - or _) that signs in to its realm, where the dev password no
#     longer does; the registration's output holds none; a second registration keeps them, one with
#     --new-passwords changes both (the old ones no longer sign in); hururaa's account sees none of them;
#   - AC-02: https://infra.c4-soft.com/ answers 200, Faito linked to its demo host, its users with their
#     groups and its groups with their roles (escaped), no password at all, a policy that allows no
#     script, X-Robots-Tag noindex; /rabbitmq/ and another path still 404;
#   - AC-08: an accounts file naming a user the realm doesn't have stops the registration, naming it,
#     the page and the passwords unchanged;
#   - AC-05: a page of an older form, then the stack deployed again with no registration: the page has
#     this form.
#
#   bash tests/0048-accounts.stand-in.sh      (bash tests/run.sh --all runs it)
#
# covers: demo/ register-app.sh registry.sh registry.txt routes.sh networks.sh registration-account.sh
# covers: caddy/ compose.yml compose.demo.yml keycloak-import/ tlds-alpha-by-domain.txt
# covers: tests/fixtures/0002/ tests/stand-in-host/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/stand-in-host.sh

FIXTURES=tests/fixtures/0002
UPLOADS=/root/apps-0048
UPLOAD=/root/c4-infra-upload
PAGE=/home/c4-infra/c4-infra/caddy/html/index.html

umask 077
work=$(mktemp -d)
trap 'stand_in_down; rm -rf "$work"' EXIT

upload() { # Faito's fixture, its realm file and a .env, rsynced to ~faito/faito/ with its key
  stand_in_exec rm -rf "$UPLOADS/faito"
  stand_in_exec mkdir -p "$UPLOADS/faito" || return 1
  (cd "$FIXTURES/faito" && tar -cf - .) | stand_in_exec -i tar -xf - --no-same-owner -C "$UPLOADS/faito" || return 1
  stand_in_exec -i sh -c 'cat > "$1/faito-realm.json"' sh "$UPLOADS/faito" < "$FIXTURES/faito-realm-named-public-facing.json" || return 1
  printf '%s\n' '# no such user' 'faito nobody -' | stand_in_exec -i sh -c 'cat > "$1/nobody.accounts"' sh "$UPLOADS/faito" || return 1
  printf 'MARKER=0048\n' | stand_in_exec -i sh -c 'umask 077 && cat > "$1/.env"' sh "$UPLOADS/faito" || return 1
  stand_in_exec bash -c 'cd "$1" && rsync -az --delete -e "$2" ./ "$3@127.0.0.1:~/$3/"' \
    sh "$UPLOADS/faito" "$(stand_in_ssh_command faito)" faito
}
register() { # <log> [sudo c4-app register option…]: as faito, its realm, its site and the options
  local log=$1
  shift
  stand_in_ssh faito "sudo c4-app register --realm faito-realm.json --proxy faito.routes $*" > "$work/$log" 2>&1
}
accounts_of() { # <account> <file>: sudo c4-app accounts as that account
  stand_in_ssh "$1" "sudo c4-app accounts" 2> /dev/null | tr -d '\r' > "$work/$2"
}
password_of() { # <file> <username>
  awk -v u="$2" '$2 == u { print $3 }' "$work/$1"
}
well_formed() { # <file>: two accounts, each password of RQ-07's form
  local password
  [ "$(awk '{ print $1, $2 }' "$work/$1" | tr '\n' ' ')" = "faito ann faito bob " ] || { echo "accounts:"; awk '{ print $1, $2 }' "$work/$1"; return 1; }
  for password in $(awk '{ print $3 }' "$work/$1"); do
    [ ${#password} -ge 24 ] && [[ $password =~ [a-z] && $password =~ [A-Z] && $password =~ [0-9] && $password =~ [-_] ]] \
      && [[ ! $password =~ [^A-Za-z0-9_-] ]] || { echo "not of RQ-07's form: ${#password} characters"; return 1; }
  done
}
# one request a check: two failures within a second would lock the account for 60 s (the stack's
# quick-login check, README "Brute-force protection")
grant() { # <username> <password>: "<status> <error>" of a password grant of the realm's admin-cli
  local answer
  printf '%s' "$2" | stand_in_exec -i sh -c 'cat > /root/grant-password'
  answer=$(stand_in_https infra.c4-soft.com /auth/realms/faito/protocol/openid-connect/token -w '\n%{http_code}' \
    -d grant_type=password -d client_id=admin-cli --data-urlencode "username=$1" --data-urlencode password@/root/grant-password \
    2> /dev/null | tr -d '\r')
  stand_in_exec rm -f /root/grant-password
  printf '%s %s' "${answer##*$'\n'}" "$(grep -o '"error":"[^"]*"' <<< "$answer" | head -n 1)"
}
signs_in() { # <username> <password>
  local result
  result=$(grant "$1" "$2")
  [ "${result%% *}" = 200 ] || { echo "token endpoint: $result"; return 1; }
}
refused_sign_in() { # <username> <password>: Keycloak 26.8.1 answers a wrong password 400 invalid_grant
  local result
  result=$(grant "$1" "$2")
  [ "$result" = '400 "error":"invalid_grant"' ] || { echo "token endpoint: $result"; return 1; }
}
holds_none() { # <log> <file of accounts>: the log holds none of their passwords
  local password
  for password in $(awk '{ print $3 }' "$work/$2"); do
    ! grep -qF -- "$password" "$work/$1" || { echo "a password in $1"; return 1; }
  done
}
fetch() { # <path>: the infra host's answer, headers then body, in $work/answer
  stand_in_https infra.c4-soft.com "$1" -D - -w '\nhttp=%{http_code}' 2>&1 | tr -d '\r' > "$work/answer"
}
answer_holds() { # <text>
  grep -qF -- "$1" "$work/answer" || { echo "answer:"; head -c 1500 "$work/answer"; return 1; }
}
answer_lacks() { # <text>
  ! grep -qF -- "$1" "$work/answer" || { echo "answer holds it:"; grep -F -- "$1" "$work/answer"; return 1; }
}
page_sum() { stand_in_exec sha256sum "$PAGE" | tr -d '\r'; }

check "the stand-in host starts" stand_in_up
check "the applications' image is loaded" stand_in_load_image "$STAND_IN_CADDY_IMAGE"
check "the accounts (c4-infra, faito, hururaa), the shared stack deployed as c4-infra" stand_in_accounts faito hururaa
check "Faito's fixture uploaded" upload

# AC-07
check "AC-07: faito registers its realm, its site and its accounts" register register-1.log --accounts faito.accounts
accounts_of faito accounts-1
check "AC-07: sudo c4-app accounts gives both accounts, each password of its form" well_formed accounts-1
check "AC-07: ann signs in with hers" signs_in ann "$(password_of accounts-1 ann)"
check "AC-07: bob too" signs_in bob "$(password_of accounts-1 bob)"
check "AC-07: ann's dev password no longer signs in" refused_sign_in ann ann-password
check "AC-07: the registration's output holds no password" holds_none register-1.log accounts-1
check "AC-07: a second registration" register register-2.log --accounts faito.accounts
accounts_of faito accounts-2
check "AC-07: keeps both passwords" cmp -s "$work/accounts-1" "$work/accounts-2"
check "AC-07: ann still signs in" signs_in ann "$(password_of accounts-1 ann)"
accounts_of hururaa accounts-hururaa
check "AC-07: hururaa's account sees no account" test ! -s "$work/accounts-hururaa"

# AC-02
fetch /
check "AC-02: / answers 200" answer_holds 'http=200'
check "AC-02: its policy allows no script, form, frame nor fetch" answer_holds \
  "content-security-policy: default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"
check "AC-02: it isn't to be indexed" answer_holds 'x-robots-tag: noindex'
check "AC-02: Faito, linked to its demo host" answer_holds '<h2><a href="https://faito.c4-soft.com/">faito</a></h2>'
check "AC-02: ann and her group" answer_holds '<li><code>ann</code> [managers]</li>'
check "AC-02: bob and his group, escaped" answer_holds '<li><code>bob</code> [a&amp;b&lt;c]</li>'
check "AC-02: managers and its roles" answer_holds '<li><code>managers</code> [manager, faito-api:read, faito-api:write]</li>'
check "AC-02: the simulated providers' users" answer_holds '<li><code>alice</code></li>'
check "AC-02: no drawn password" holds_none answer accounts-1
check "AC-02: no dev password, the application's nor the simulated providers'" \
  eval 'answer_lacks ann-password && answer_lacks alice-password'
fetch /rabbitmq/
check "AC-02: /rabbitmq/ still 404" answer_holds 'http=404'
fetch /nowhere
check "AC-02: another path still 404" answer_holds 'http=404'

# AC-07, --new-passwords
check "AC-07: a registration with --new-passwords" register register-3.log --accounts faito.accounts --new-passwords
accounts_of faito accounts-3
check "AC-07: both passwords changed" eval '[ "$(password_of accounts-3 ann)" != "$(password_of accounts-1 ann)" ] && [ "$(password_of accounts-3 bob)" != "$(password_of accounts-1 bob)" ]'
check "AC-07: the new one signs in" signs_in ann "$(password_of accounts-3 ann)"
check "AC-07: the old one no longer does" refused_sign_in ann "$(password_of accounts-1 ann)"
check "AC-07: that registration's output holds no password" holds_none register-3.log accounts-3

# AC-08
before=$(page_sum)
register register-4.log --accounts nobody.accounts
status=$?
check "AC-08: an account the realm doesn't have stops the registration" test "$status" -ne 0
check "AC-08: it names the account" grep -qF 'faito nobody: realm faito has no such user' "$work/register-4.log"
check "AC-08: the page unchanged" test "$(page_sum)" = "$before"
accounts_of faito accounts-4
check "AC-08: the passwords unchanged" cmp -s "$work/accounts-3" "$work/accounts-4"

# AC-05
stand_in_exec sh -c 'printf "<p>an older form</p>\n" > "$1"' sh "$PAGE"
redeploy_stack() { # the upload rsynced again as c4-infra, as stand_in_accounts does, then demo/deploy.sh
  stand_in_exec bash -c 'cd "$1" && rsync -az -e "$2" ./ c4-infra@127.0.0.1:~/c4-infra/' \
    sh "$UPLOAD" "$(stand_in_ssh_command c4-infra)" || return 1
  stand_in_ssh c4-infra "cd ~/c4-infra && bash ./demo/deploy.sh < /dev/null > ~/deploy-0048.log 2>&1" \
    || { stand_in_exec tail -n 30 /home/c4-infra/deploy-0048.log; return 1; }
}
check "AC-05: the stack deployed again, no registration" redeploy_stack
fetch /
check "AC-05: the page has this form again" answer_holds '<meta name="robots" content="noindex">'
check "AC-05: with Faito's accounts as its last registration read them" answer_holds '<li><code>ann</code> [managers]</li>'
finish
