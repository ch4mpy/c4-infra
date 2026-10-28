#!/usr/bin/env bash
# 0015: the facts of the stack's proxy (c4-infra/reverse-proxy: Caddy 2.11.4 with the rate-limit
# module) that a front end's own headers rest on, in a throwaway proxy in front of throwaway upstreams
# (one sending its own Content-Security-Policy, X-Frame-Options and Referrer-Policy, no
# Permissions-Policy; one sending none; one sending Content-Security-Policy-Report-Only only; a host
# that doesn't answer):
#
#   (a) `header { ?A ?B ?C }` in one block defaults all or nothing: the first upstream doesn't get the
#       Permissions-Policy it lacks;
#   (b) one `header ?<field>` directive per field defaults header by header: the upstream's values
#       once, unchanged, the missing one set; the Report-Only one gets the enforced default beside it;
#   (c) a snippet of `header {args[0]}<field> "<value>"` lines, imported with "" sets the values as a
#       plain `header` does (the upstream's and the shared one, both), with ? defaults them;
#   (d) handle_errors in the site's snippet, importing the common headers and, on a `vars` marker the
#       route sets, the defaults: the proxy's own 413 (request_body) and 502 then carry nosniff,
#       Referrer-Policy, no Server, and on the marked route the three defaults; status and empty
#       body unchanged; without it, a 502 carries Server and none of them;
#   (e) the rate limit's 429, through that handle_errors, keeps its Retry-After and gets nosniff and
#       no Server.
#
#   bash tests/0015-proxy-facts.sh
#
# Needs the image c4-infra/reverse-proxy (up.sh builds it). Its containers and network are removed
# whatever happens.
#
# covers: reverse-proxy/ caddy/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

PROXY_IMAGE=c4-infra/reverse-proxy
UPSTREAM_IMAGE=caddy:2.11.4-alpine
NAME=c4-infra-test-0015-facts
PORT=48415

host_path() { if command -v cygpath > /dev/null; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

work=$(mktemp -d)
cleanup() {
  docker rm -f $(docker ps -aq -f "name=^$NAME-") > /dev/null 2>&1
  docker network rm "$NAME" > /dev/null 2>&1
  rm -rf "$work"
}
trap cleanup EXIT
cleanup
mkdir -p "$work/conf"

upstream() { # <kind>, its header lines on stdin
  { printf '{\n\tadmin off\n\tauto_https off\n}\n:80 {\n'; cat; printf '\trespond "%s"\n}\n' "$1"; } > "$work/conf/$1.caddy"
}
upstream own <<'EOF'
	header Content-Security-Policy "default-src 'none'"
	header X-Frame-Options "SAMEORIGIN"
	header Referrer-Policy "unsafe-url"
EOF
upstream none < /dev/null
upstream report-only <<'EOF'
	header Content-Security-Policy-Report-Only "default-src 'none'"
EOF
cat > "$work/conf/proxy.caddy" <<'EOF'
{
	auto_https off
}
(common-headers) {
	header {
		X-Content-Type-Options "nosniff"
		Referrer-Policy "strict-origin-when-cross-origin"
		-Server
	}
}
(values) {
	header {args[0]}Content-Security-Policy "default-src 'self'"
	header {args[0]}X-Frame-Options "DENY"
	header {args[0]}Permissions-Policy "camera=()"
}
(spa) {
	import values ""
}
(site) {
	import common-headers
	handle_errors {
		import common-headers
		@app vars app_headers yes
		handle @app {
			import values ?
		}
	}
}
:8080 {
	import site
	handle /block/* {
		header {
			?Content-Security-Policy "default-src 'self'"
			?X-Frame-Options "DENY"
			?Permissions-Policy "camera=()"
		}
		reverse_proxy own:80
	}
	handle /each/* {
		import values ?
		reverse_proxy own:80
	}
	handle /each-none/* {
		import values ?
		reverse_proxy none:80
	}
	handle /each-report-only/* {
		import values ?
		reverse_proxy report-only:80
	}
	handle /spa/* {
		import spa
		reverse_proxy none:80
	}
	handle /app-upload/* {
		vars app_headers yes
		import values ?
		request_body {
			max_size 1KB
		}
		reverse_proxy none:80
	}
	handle /app-down/* {
		vars app_headers yes
		import values ?
		reverse_proxy nowhere:80
	}
	handle /down/* {
		reverse_proxy nowhere:80
	}
	handle /limited/* {
		route {
			rate_limit {
				zone facts {
					key {remote_host}
					events 1
					window 1m
				}
			}
			respond "limited"
		}
	}
}
:8081 {
	import common-headers
	handle /down/* {
		reverse_proxy nowhere:80
	}
}
EOF

docker network create "$NAME" > /dev/null
for kind in own none report-only; do
  MSYS_NO_PATHCONV=1 docker run -d --name "$NAME-$kind" --network "$NAME" --network-alias "$kind" \
    -v "$(host_path "$work/conf"):/conf:ro" "$UPSTREAM_IMAGE" caddy run --config "/conf/$kind.caddy" --adapter caddyfile > /dev/null
done
MSYS_NO_PATHCONV=1 docker run -d --name "$NAME-proxy" --network "$NAME" -p "127.0.0.1:$PORT:8080" -p "127.0.0.1:$((PORT + 1)):8081" \
  -v "$(host_path "$work/conf"):/conf:ro" "$PROXY_IMAGE" caddy run --config /conf/proxy.caddy --adapter caddyfile > /dev/null

# <path> [<port>] [curl options…]: the response's headers into $work/h (lower-case names), its body into $work/b
get() {
  local path=$1 port=${2:-$PORT}
  shift 2 2> /dev/null || shift $#
  curl -s -o "$work/b" -D - "$@" "http://127.0.0.1:$port$path" | tr -d '\r' \
    | awk -F': ' 'NR == 1 { print; next } NF > 1 { printf "%s: %s\n", tolower($1), substr($0, length($1) + 3) }' > "$work/h"
}
answers() {
  local i
  for ((i = 0; i < 40; i++)); do
    get /each/x
    grep -q '^HTTP/1.1 200' "$work/h" && return 0
    sleep 0.5
  done
  cat "$work/h"
  return 1
}
count() { grep -c "^$1: " "$work/h"; }
value() { sed -n "s/^$1: //p" "$work/h"; }
has() { # <name> <value>: once, with that value
  [ "$(count "$1")" -eq 1 ] && [ "$(value "$1")" = "$2" ] || { echo "$1:"; grep "^$1: " "$work/h"; return 1; }
}
lacks() { ! grep "^$1: " "$work/h"; }
status_is() { head -n 1 "$work/h" | grep -q " $1" || { head -n 1 "$work/h"; return 1; }; }

check "the throwaway proxy and upstreams answer" answers

get /block/x
check "(a) one block of ?: the upstream's Content-Security-Policy, once" has content-security-policy "default-src 'none'"
check "(a) one block of ?: no default Permissions-Policy (all or nothing)" lacks permissions-policy

get /each/x
check "(b) one ? per field: the upstream's Content-Security-Policy, once" has content-security-policy "default-src 'none'"
check "(b) its X-Frame-Options, once" has x-frame-options SAMEORIGIN
check "(b) the missing Permissions-Policy set" has permissions-policy "camera=()"
get /each-none/x
check "(b) an upstream sending none: the three defaults" \
  eval 'has content-security-policy "default-src '"'"'self'"'"'" && has x-frame-options DENY && has permissions-policy "camera=()"'
get /each-report-only/x
check "(b) a Report-Only upstream: the default policy enforced" has content-security-policy "default-src 'self'"
check "(b) and its Report-Only kept" has content-security-policy-report-only "default-src 'none'"

get /spa/x
check "(c) the snippet imported with \"\" sets the values" \
  eval 'has content-security-policy "default-src '"'"'self'"'"'" && has x-frame-options DENY && has permissions-policy "camera=()"'

get /app-upload/x "" -X POST --data-binary "@$work/conf/proxy.caddy" -H 'Content-Type: text/plain'
check "(d) a body over max_size: 413" status_is 413
check "(d) the 413 carries nosniff" has x-content-type-options nosniff
check "(d) and Referrer-Policy" has referrer-policy strict-origin-when-cross-origin
check "(d) and no Server" lacks server
check "(d) and, on the marked route, the three defaults" \
  eval 'has content-security-policy "default-src '"'"'self'"'"'" && has x-frame-options DENY && has permissions-policy "camera=()"'
check "(d) its body is empty" test ! -s "$work/b"
get /app-down/x
check "(d) a front end that doesn't answer: 502" status_is 502
check "(d) the 502 carries nosniff, no Server, the three defaults" \
  eval 'has x-content-type-options nosniff && lacks server && has x-frame-options DENY && has permissions-policy "camera=()"'
get /down/x
check "(d) an unmarked route's 502: nosniff, no Server" eval 'has x-content-type-options nosniff && lacks server'
check "(d) and none of the three defaults" eval 'lacks content-security-policy && lacks x-frame-options && lacks permissions-policy'
get /down/x $((PORT + 1))
check "(d) common-headers without handle_errors: a 502 carries Server and no nosniff (what 0015 fixes)" \
  eval 'grep -q "^server: " "$work/h" && lacks x-content-type-options'

get /limited/x
get /limited/x
check "(e) the rate limit's second request: 429" status_is 429
check "(e) the 429 keeps its Retry-After" grep -q '^retry-after: ' "$work/h"
check "(e) and carries nosniff, no Server" eval 'has x-content-type-options nosniff && lacks server'
finish
