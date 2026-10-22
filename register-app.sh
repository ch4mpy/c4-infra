#!/usr/bin/env bash
# Registers an application with the shared stack, in dev as on the demo host. Idempotent: each
# application's deployment runs it every time.
#
#   register-app.sh --app <name> [--realm <file>]... [--themes <dir>] [--proxy <file>]
#                   [--rabbitmq-user <user> --rabbitmq-password-env <variable>] [--reset-realms]
#
#   --realm         a realm export (kc.sh export --users realm_file), named <realm>-realm.json. The
#                   realm is imported only when Keycloak doesn't have it yet, so that the users and
#                   clients created since survive; --reset-realms deletes it first.
#   --themes        a directory of Keycloak themes, one sub-directory per theme
#   --proxy         the application's server block: an nginx .conf in dev (PROXY=nginx in .env), a
#                   Caddyfile site on the demo host (PROXY=caddy)
#   --rabbitmq-*    a virtual host named after the application, and its user, with every permission
#                   on that virtual host and none elsewhere; the password is read from the named
#                   environment variable (the one the application itself reads)
#   --index-only    only rewrite the dev landing page (https://host.docker.internal/)
#
# No password ever goes on a command line (the host's process list and `docker inspect` show
# them): Keycloak's admin CLI reads it from its environment, RabbitMQ gets a salted hash.
set -euo pipefail
# Git Bash would rewrite the container paths below (/opt/keycloak/...) into Windows paths
export MSYS_NO_PATHCONV=1

INFRA_DIR=$(cd "$(dirname "$0")" && pwd)

# The value of KEY in .env, read as data rather than sourced: the demo's .env is written for
# compose, which un-escapes "$$" and takes everything after the first "=" as is.
env_value() {
  local line
  line=$(grep -m1 "^$1=" "$INFRA_DIR/.env" || true)
  line=${line#*=}
  printf '%s' "${line//\$\$/\$}"
}

PROXY=$(env_value PROXY)
APPS_DOMAIN=$(env_value APPS_DOMAIN)

KEYCLOAK=c4-infra.keycloak
RABBITMQ=c4-infra.rabbitmq
REVERSE_PROXY=c4-infra.reverse-proxy

app=""
realms=()
themes=""
proxy=""
rabbitmq_user=""
rabbitmq_password_env=""
reset_realms=false
index_only=false
while [ $# -gt 0 ]; do
  case "$1" in
    --app) app=$2; shift 2 ;;
    --realm) realms+=("$2"); shift 2 ;;
    --themes) themes=$2; shift 2 ;;
    --proxy) proxy=$2; shift 2 ;;
    --rabbitmq-user) rabbitmq_user=$2; shift 2 ;;
    --rabbitmq-password-env) rabbitmq_password_env=$2; shift 2 ;;
    --reset-realms) reset_realms=true; shift ;;
    --index-only) index_only=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# The dev landing page links the shared services and every registered application
write_index() {
  [ "$PROXY" = nginx ] || return 0
  mkdir -p "$INFRA_DIR/nginx/html"
  {
    echo '<!doctype html><html lang="en"><head><meta charset="utf-8"><title>c4-infra</title></head><body>'
    echo '<h1>Shared services</h1><ul>'
    echo '<li><a href="/auth/admin/">Keycloak</a></li><li><a href="/mailpit/">Mailpit</a></li>'
    echo '<li><a href="/grafana/">Grafana</a></li><li><a href="/rabbitmq/">RabbitMQ</a></li></ul>'
    echo '<h1>Applications</h1><ul>'
    for conf in "$INFRA_DIR"/nginx/apps/*.conf; do
      [ -f "$conf" ] || continue
      name=$(basename "$conf" .conf)
      echo "<li><a href=\"https://${name}.${APPS_DOMAIN}/\">${name}</a></li>"
    done
    echo '</ul></body></html>'
  } > "$INFRA_DIR/nginx/html/index.html"
}

if $index_only; then
  write_index
  exit 0
fi

if [ -z "$app" ]; then
  echo "--app <name> is required" >&2
  exit 1
fi
if [ -n "$rabbitmq_user" ] && { ! [[ "$rabbitmq_password_env" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || [ -z "${!rabbitmq_password_env:-}" ]; }; then
  echo "--rabbitmq-user needs --rabbitmq-password-env <a variable holding the password>" >&2
  exit 1
fi

# Keycloak: the admin CLI inside the container, over the plain HTTP port of the Docker network,
# each call authenticated on its own (no stored session: a registration makes one or two calls).
# The registration depends on the bootstrap administrator of .env: replacing it in the admin
# console, or changing its password there, makes the registrations fail (see README.md).
if [ ${#realms[@]} -gt 0 ]; then
  KC_CLI_PASSWORD=$(env_value KC_BOOTSTRAP_ADMIN_PASSWORD)
  export KC_CLI_PASSWORD
  kc_admin=$(env_value KC_BOOTSTRAP_ADMIN_USERNAME)
  # `kcadm -i ...` only where the input is redirected: a deployment may run this script from a
  # heredoc on ssh's stdin, which `docker exec -i` would otherwise swallow
  kcadm() {
    local exec_options=()
    if [ "$1" = -i ]; then
      exec_options=(-i)
      shift
    fi
    docker exec "${exec_options[@]}" -e KC_CLI_PASSWORD "$KEYCLOAK" /opt/keycloak/bin/kcadm.sh "$@" \
      --no-config --server http://localhost:8080/auth --realm master --user "$kc_admin"
  }
  for file in "${realms[@]}"; do
    realm=$(basename "$file" -realm.json)
    if kcadm get "realms/$realm" --fields realm > /dev/null 2>&1; then
      if $reset_realms; then
        echo "Deleting realm $realm"
        kcadm delete "realms/$realm"
      else
        echo "Realm $realm: already in Keycloak, left as it is"
        continue
      fi
    fi
    echo "Importing realm $realm"
    # on stdin: nothing to copy into the container, whatever the file's owner and mode
    kcadm -i create realms -f - < "$file"
  done
fi

# Themes: copied into the directory Keycloak reads; it caches them, so a change needs a restart
if [ -n "$themes" ]; then
  changed=false
  for dir in "$themes"/*/; do
    [ -d "$dir" ] || continue
    name=$(basename "$dir")
    target="$INFRA_DIR/keycloak/themes/$name"
    if [ ! -d "$target" ] || ! diff -r "$dir" "$target" > /dev/null 2>&1; then
      rm -rf "$target"
      cp -r "$dir" "$target"
      changed=true
      echo "Theme $name installed"
    fi
  done
  if $changed; then
    echo "Restarting Keycloak to load the themes"
    docker restart "$KEYCLOAK" > /dev/null
  fi
fi

# RabbitMQ: a virtual host per application, and its user. Imported as definitions (created, or
# updated in place: permissions, connections and the other applications are left alone), with
# the password as a salted SHA-256 hash, RabbitMQ's own format. rabbitmqctl doesn't read them from
# its standard input: the file goes into the container first.
if [ -n "$rabbitmq_user" ]; then
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  openssl rand 4 > "$work/salt"
  password=${!rabbitmq_password_env}
  { cat "$work/salt"; printf '%s' "${password%$'\r'}"; } | openssl dgst -sha256 -binary > "$work/digest"
  hash=$(cat "$work/salt" "$work/digest" | openssl base64 -A)
  cat > "$work/definitions.json" <<EOF
{
  "vhosts": [{ "name": "$app" }],
  "users": [{ "name": "$rabbitmq_user", "password_hash": "$hash",
              "hashing_algorithm": "rabbit_password_hashing_sha256", "tags": [] }],
  "permissions": [{ "user": "$rabbitmq_user", "vhost": "$app",
                    "configure": ".*", "write": ".*", "read": ".*" }]
}
EOF
  docker exec -i "$RABBITMQ" sh -c \
    'cat > "$1" && rabbitmqctl -q import_definitions "$1" > /dev/null; status=$?; rm -f "$1"; exit $status' \
    sh "/tmp/$app-definitions.json" < "$work/definitions.json"
  echo "RabbitMQ: virtual host $app, user $rabbitmq_user"
fi

# Reverse proxy: the application's server block, checked before it is kept (and left alone, with
# no reload, when it hasn't changed)
if [ -n "$proxy" ]; then
  case "$PROXY" in
    nginx)
      target="$INFRA_DIR/nginx/apps/$app.conf"
      check=(nginx -c /etc/nginx/c4-infra/nginx.conf -t -q)
      reload=(nginx -c /etc/nginx/c4-infra/nginx.conf -s reload)
      ;;
    caddy)
      target="$INFRA_DIR/caddy/apps/$app.caddy"
      check=(caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile)
      reload=(caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile)
      ;;
    *)
      echo "PROXY must be nginx or caddy, not '$PROXY'" >&2
      exit 1
      ;;
  esac
  if [ -f "$target" ] && cmp -s "$proxy" "$target"; then
    echo "Reverse proxy: $app server unchanged"
  else
    backup=$(mktemp)
    had_previous=false
    if [ -f "$target" ]; then
      cp "$target" "$backup"
      had_previous=true
    fi
    cp "$proxy" "$target"
    if ! docker exec "$REVERSE_PROXY" "${check[@]}"; then
      if $had_previous; then cp "$backup" "$target"; else rm -f "$target"; fi
      rm -f "$backup"
      echo "The server block $proxy is invalid: the reverse proxy keeps its previous configuration" >&2
      exit 1
    fi
    if ! docker exec "$REVERSE_PROXY" "${reload[@]}"; then
      # removed, or restored: the next run installs it again rather than finding it "unchanged"
      if $had_previous; then cp "$backup" "$target"; else rm -f "$target"; fi
      rm -f "$backup"
      echo "The reverse proxy could not reload: $proxy is not installed" >&2
      exit 1
    fi
    rm -f "$backup"
    write_index
    echo "Reverse proxy: $app server installed"
  fi
fi
