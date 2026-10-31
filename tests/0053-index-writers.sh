#!/usr/bin/env bash
# 0053: two writers of the landing page at once (two registrations, a registration and a deployment)
# leave one whole page, one or the other, never a mix (AC-03): in a scratch stack, two
# `register-app.sh --index-only` started together, ten times, the second's registry naming fewer
# applications, so that their pages differ. Each time the page starts with <!doctype html>, ends
# with </body></html>, holds one <!doctype and is one of the two pages; no temporary page nor lock
# is left. No Docker.
#
#   bash tests/0053-index-writers.sh
#
# covers: register-app.sh registry.sh routes.sh registration-account.sh tests/fixtures/0004/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

ROUNDS=10
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

stack=$work/stack
mkdir -p "$stack/caddy/apps" "$stack/keycloak-import"
cp registry.sh routes.sh networks.sh register-app.sh registration-account.sh tlds-alpha-by-domain.txt "$stack/"
cp keycloak-import/simulated-*-realm.json "$stack/keycloak-import/"
printf '%s\n' INFRA_ENV=dev > "$stack/.env"
all=$PWD/tests/fixtures/0004/entries.txt
grep -E '^[1-3] ' "$all" > "$work/fewer.txt"
# every application of the fixture registered, with accounts, so that writing a page takes a while
for app in turu hururaa tickee faito verif-a verif-b; do
  echo '# site' > "$stack/caddy/apps/$app.caddy"
  for ((i = 0; i < 40; i++)); do printf 'U\037%s-user-%d\037password-%d\037group-%d\n' "$app" "$i" "$i" "$i"; done \
    > "$stack/caddy/apps/$app.accounts"
done

index() { # <registry file>: the page that registry gives, into $stack/caddy/html/index.html
  REGISTRY_FILE=$1 bash "$stack/register-app.sh" --index-only
}

page=$stack/caddy/html/index.html
index "$all" && cp "$page" "$work/all.html"
index "$work/fewer.txt" && cp "$page" "$work/fewer.html"
check "the two registries give two pages" eval '! cmp -s "$work/all.html" "$work/fewer.html"'

whole() { # one page, one of the two
  [ "$(head -c 15 "$page")" = '<!doctype html>' ] || { echo "starts with:"; head -c 80 "$page"; return 1; }
  [ "$(tail -n 1 "$page")" = '</body></html>' ] || { echo "ends with:"; tail -n 2 "$page"; return 1; }
  [ "$(grep -o '<!doctype' "$page" | wc -l)" -eq 1 ] || { echo "<!doctype more than once"; return 1; }
  cmp -s "$page" "$work/all.html" || cmp -s "$page" "$work/fewer.html" || { echo "neither page:"; cat "$page"; return 1; }
}

nothing_left() {
  local left
  left=$(find "$stack/caddy/html" -mindepth 1 -name '.index*')
  [ -z "$left" ] || { echo "left: $left"; return 1; }
}

for ((round = 1; round <= ROUNDS; round++)); do
  index "$all" > "$work/a.log" 2>&1 &
  a=$!
  index "$work/fewer.txt" > "$work/b.log" 2>&1 &
  b=$!
  wait "$a"
  status_a=$?
  wait "$b"
  status_b=$?
  check "round $round: both writers end well" eval '[ "$status_a" -eq 0 ] && [ "$status_b" -eq 0 ] || { cat "$work/a.log" "$work/b.log"; false; }'
  check "round $round: one whole page, one of the two" whole
  check "round $round: no temporary page nor lock left" nothing_left
done

finish
