#!/usr/bin/env bash
# 0053: the facts of a page replaced under the proxy's bind mount, in a throwaway container of the
# stack's proxy image that mounts a directory read-only as the stack does (./caddy/:/etc/caddy/:ro,
# compose.yml) and serves its html/index.html as caddy/Caddyfile serves the landing page. Five pages
# each way; each read right after the write, then 1 s later, through the container's own port (what
# the proxy serves) and with cat (what the mount shows):
#
#   (r) a new file renamed over the old one (register-app.sh's write_index before 0053): recorded,
#       not asserted (`fact: …` lines), since it is the platform's behaviour: fresh on the Windows
#       workstation, stale on the Linux one (Docker Desktop), 2026-10-31;
#   (a) the new content written into the existing file, its inode kept (write_index since 0053):
#       asserted fresh at once, every time, after (r)'s renames as after a deployment of the fix.
#
#   bash tests/0053-mount-facts.sh
#
# Needs the image c4-infra/reverse-proxy (up.sh builds it), and with Docker Desktop a TMPDIR it shares.
# Its container is removed whatever happens.
#
# covers: reverse-proxy/ caddy/Caddyfile register-app.sh
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/docker-preflight.sh
mapfile -t C4_LABELS < <(docker_labels c4-infra)

PROXY_IMAGE=c4-infra/reverse-proxy
NAME=c4-infra-test-0053-facts
PAGES=5

host_path() { if command -v cygpath > /dev/null; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

remove_proxy() { docker rm -f -v "$NAME" > /dev/null 2>&1; }
remove_proxy
work=$(mktemp -d)
trap 'remove_proxy; rm -rf "$work"' EXIT
mkdir -p "$work/caddy/html"
cat > "$work/caddy/Caddyfile" <<'EOF'
{
	admin off
	auto_https off
}
:8080 {
	root * /etc/caddy/html
	rewrite * /index.html
	file_server
}
EOF

page() { # <marker>: a page of a few kB, as the landing page, that names its marker
  printf '<!doctype html><html><body><h1>%s</h1>\n' "$1"
  for ((line = 0; line < 60; line++)); do printf '<p>%s line %d of the page</p>\n' "$1" "$line"; done
  echo '</body></html>'
}
page start > "$work/caddy/html/index.html"
chmod 644 "$work/caddy/html/index.html"

if ! MSYS_NO_PATHCONV=1 docker run "${C4_LABELS[@]}" -d --name "$NAME" -v "$(host_path "$work/caddy"):/etc/caddy:ro" \
  "$PROXY_IMAGE" caddy run --config /etc/caddy/Caddyfile --adapter caddyfile > /dev/null; then
  check "the throwaway proxy starts ($PROXY_IMAGE)" false
  finish
fi

served() { MSYS_NO_PATHCONV=1 docker exec "$NAME" wget -qO- http://127.0.0.1:8080/ 2> /dev/null; }
mounted() { MSYS_NO_PATHCONV=1 docker exec "$NAME" cat /etc/caddy/html/index.html 2> /dev/null; }

answers() {
  local i
  for ((i = 0; i < 40; i++)); do
    served | grep -qF '<h1>start</h1>' && return 0
    sleep 0.5
  done
  echo "served:"
  served | head -n 3
  return 1
}

replace_r() { # <marker>: a new file, renamed over the old one
  local tmp
  tmp=$(mktemp "$work/caddy/html/.index.XXXXXX")
  page "$1" > "$tmp"
  chmod 644 "$tmp"
  mv "$tmp" "$work/caddy/html/index.html"
}

replace_a() { # <marker>: the new content written into the existing file
  local tmp
  tmp=$(mktemp "$work/caddy/html/.index.XXXXXX")
  page "$1" > "$tmp"
  cat "$tmp" > "$work/caddy/html/index.html"
  rm -f "$tmp"
}

fresh() { # <reader> <marker>: yes when what the reader gets is the marker's page
  if "$1" | grep -qF "<h1>$2</h1>"; then echo yes; else echo no; fi
}

# measure <way>: prints one `fact:` line per page and read; sets stale_at_once to the count of
# reads right after the write that weren't fresh
measure() {
  local way=$1 n marker s m s1 m1
  stale_at_once=0
  for ((n = 1; n <= PAGES; n++)); do
    marker="$way-$n"
    "replace_$way" "$marker"
    s=$(fresh served "$marker")
    m=$(fresh mounted "$marker")
    sleep 1
    s1=$(fresh served "$marker")
    m1=$(fresh mounted "$marker")
    echo "fact: ($way) page $n, at once: served $s, mounted $m; after 1 s: served $s1, mounted $m1"
    [ "$s" = yes ] && [ "$m" = yes ] || stale_at_once=$((stale_at_once + 1))
  done
}

check "the throwaway proxy serves the mounted page" answers

measure r
echo "fact: (r) rename fresh at once: $([ "$stale_at_once" -eq 0 ] && echo yes || echo "no, $stale_at_once of $PAGES stale")"

measure a
echo "fact: (a) in place fresh at once: $([ "$stale_at_once" -eq 0 ] && echo yes || echo "no, $stale_at_once of $PAGES stale")"
check "(a) the content written into the existing file: served and mounted fresh at once, every time" \
  test "$stale_at_once" -eq 0

finish
