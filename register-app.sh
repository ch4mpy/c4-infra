#!/usr/bin/env bash
# Registers an application with the shared stack, in dev as on the demo host. Idempotent: each
# application's deployment runs it every time.
#
#   register-app.sh --app <name> [--realm <file>]... [--themes <dir>] [--proxy <routes file>]
#                   [--rabbitmq-user <user> --rabbitmq-password-env <variable>] [--reset-realms]
#
#   --app           the application's name in the registry, registry.txt: an application missing
#                   from it, or a registry that registry.sh's check refuses, registers nothing
#   --realm        a realm export (kc.sh export --users realm_file), named <realm>-realm.json, for
#                   a realm of the application's registry entry. The realm is imported only when
#                   Keycloak doesn't have it yet, so that the users and clients created since
#                   survive; --reset-realms deletes it first. It is imported under the name of the
#                   file: the file's own "realm" field can't name another.
#   --themes        a directory of Keycloak themes, one sub-directory per theme of the application's
#                   registry entry: a new or changed one shows on reload in dev; on the demo host, it
#                   restarts Keycloak (once). A theme holding a link or a special file, or a
#                   theme.properties holding ${ (as Java reads it) or a byte outside printable ASCII,
#                   is refused (intent 0012)
#   --proxy         the application's routes file (README.md, "Routes file"), the same in both
#                   environments: its site on the reverse proxy is generated from it and from the
#                   application's registry entry, for the environment INFRA_ENV (.env) names (dev
#                   or demo: the host name and the upstreams)
#   --rabbitmq-*    a virtual host named after the application, and its user (the registry entry's),
#                   with every permission on that virtual host and none elsewhere; the password is
#                   read from the named environment variable (the one the application itself reads)
#   --index-only    only rewrite the dev landing page (https://host.docker.internal/)
#
# Every registration also makes sure of the application's own network, c4-infra.<app>, with the
# shared services attached to it (networks.sh ensure, intent 0007).
#
# A registration touches only what the application's registry entry assigns to it (intent 0002): a
# realm, a theme or a RabbitMQ user of another entry, or of none, registers nothing. On the demo
# host, an application's account runs it through the root-owned demo/c4-app, for its own name only;
# what it writes here then belongs to this directory's owner, as the deployment's own files.
#
# No password ever goes on a command line (the host's process list and `docker inspect` show
# them): Keycloak's admin CLI reads the registration account's secret from its environment,
# RabbitMQ gets a salted hash.
set -euo pipefail
# Git Bash would rewrite the container paths below (/opt/keycloak/...) into Windows paths
export MSYS_NO_PATHCONV=1

INFRA_DIR=$(cd "$(dirname "$0")" && pwd)
source "$INFRA_DIR/registry.sh"
source "$INFRA_DIR/routes.sh"
# the registration account's login and realm probe (account_login, account, probe), and KEYCLOAK
source "$INFRA_DIR/registration-account.sh"

# Run as root (demo/c4-app), what a registration writes under the stack's directory gets that
# directory's owner: the shared stack's account, which the next deployment runs as
own() { # <path>…
  [ "$(id -u)" -eq 0 ] || return 0
  chown -R --reference="$INFRA_DIR" "$@"
}

RABBITMQ=c4-infra.rabbitmq

# What a registration leaves behind, removed on exit whatever happens: the admin CLI's session in
# the Keycloak container, RabbitMQ's working directory
kc_session=""
work=""
cleanup() {
  if [ -n "$kc_session" ]; then
    docker exec "$KEYCLOAK" rm -f "$kc_session" > /dev/null 2>&1 || true
  fi
  if [ -n "$work" ]; then
    rm -rf "$work"
  fi
}
trap cleanup EXIT
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

# The environment, read at each run: it picks the site's host name and upstreams. The running
# proxy's own rules (caddy/env/<INFRA_ENV>.caddy) are those of the INFRA_ENV it was started with:
# this script only validates and reloads it, never restarts nor recreates it.
stack_env_read INFRA_ENV INFRA_ENV
case "$INFRA_ENV" in
  dev | demo) ;;
  *)
    echo "INFRA_ENV in $INFRA_DIR/.env must be dev or demo, not '$INFRA_ENV' (env.sh writes it in dev, demo/write-env.sh on the demo host); nothing was registered." >&2
    exit 1
    ;;
esac

# The dev landing page links the shared services and every registered application, on its dev
# host name (registry.txt)
write_index() {
  local site name host
  [ "$INFRA_ENV" = dev ] || return 0
  mkdir -p "$INFRA_DIR/caddy/html"
  {
    echo '<!doctype html><html lang="en"><head><meta charset="utf-8"><title>c4-infra</title></head><body>'
    echo '<h1>Shared services</h1><ul>'
    echo '<li><a href="/auth/admin/">Keycloak</a></li><li><a href="/mailpit/">Mailpit</a></li>'
    echo '<li><a href="/grafana/">Grafana</a></li><li><a href="/rabbitmq/">RabbitMQ</a></li></ul>'
    echo '<h1>Applications</h1><ul>'
    for site in "$INFRA_DIR"/caddy/apps/*.caddy; do
      [ -f "$site" ] || continue
      name=$(basename "$site" .caddy)
      # in a subshell: registry_entry sets the REG_* of the application being registered
      host=$(registry_entry "$name" 2> /dev/null && printf '%s' "$REG_DEV_HOST") || continue
      echo "<li><a href=\"https://${host}/\">${name}</a></li>"
    done
    echo '</ul></body></html>'
  } > "$INFRA_DIR/caddy/html/index.html"
  own "$INFRA_DIR/caddy/html"
}

if $index_only; then
  write_index
  exit 0
fi

if [ -z "$app" ]; then
  echo "--app <name> is required" >&2
  exit 1
fi
# Before anything changes in the shared stack: a valid registry, which holds this application
if ! registry_check; then
  echo "The registry is invalid (above): fix registry.txt; nothing was registered." >&2
  exit 1
fi
registry_entry "$app" || exit 1
if [ -n "$rabbitmq_user" ] && { ! [[ "$rabbitmq_password_env" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || [ -z "${!rabbitmq_password_env:-}" ]; }; then
  echo "--rabbitmq-user needs --rabbitmq-password-env <a variable holding the password>" >&2
  exit 1
fi

# Only what the registry entry assigns to the application, before anything changes: each realm
# (from its file's name, the name it is imported under), each theme (its directory's name) and the
# RabbitMQ user must be the entry's
in_entry() { # <value> <comma-separated list of the entry>
  [[ ",$2," == *",$1,"* ]]
}

# What a theme may hold, checked before anything changes too (intent 0012). Keycloak resolves ${…}
# in a theme.properties from its own environment and Java's system properties, and the theme's pages
# show the values (the master realm's administrator's password among them); it serves a theme's
# files, a link's target included (/proc/self/environ: its whole environment). A theme holding
# either registers nothing. A theme.properties is read as Java's Properties reads it, and what this
# check can't read the same way is refused too (a NUL byte, which bash drops; a file it can't read);
# it holds printable ASCII only, tab, form feed and line ends aside (spec v2: Java reads it as UTF-8,
# or ISO-8859-1 when it isn't, and a byte beyond ASCII is written \uXXXX).

# $decoded: a logical line of a properties file, Java's escapes decoded (\uXXXX, \t \n \r \f, \<c> → <c>),
# from one backslash to the next
properties_decode() { # <logical line>
  local in=$1 c
  decoded=""
  while [[ $in == *\\* ]]; do
    decoded+=${in%%\\*}
    in=${in#*\\}
    c=${in:0:1}
    case $c in
      '') decoded+='\'; break ;;
      u)
        if [[ ${in:1:4} =~ ^[0-9A-Fa-f]{4}$ ]]; then
          printf -v c "\\u${in:1:4}"
          decoded+=$c
          in=${in:5}
          continue
        fi ;;
      t) c=$'\t' ;;
      n) c=$'\n' ;;
      r) c=$'\r' ;;
      f) c=$'\f' ;;
    esac
    decoded+=$c
    in=${in:1}
  done
  decoded+=$in
}

# Adds to theme_problems what is wrong with a theme.properties, "<shown name>[:<line>]: …": a byte
# outside printable ASCII (the tab, CR, LF and form feed besides), and each logical line holding ${
# once read as Java reads it. In ASCII, Keycloak's decodings (UTF-8, or ISO-8859-1 when the file isn't
# UTF-8) and this check, which reads bytes (the C locale, whatever the caller's), see the same
# characters; any other is written \uXXXX. Lines end at LF, CRLF or CR; Java's blanks are the space,
# the tab and the form feed; a line whose trailing backslashes are odd in number continues on the next
# one, its leading blanks dropped; a line starting with # or ! (after blanks) is a comment, never
# continued, even after a continued line that holds nothing yet (Java's reader is still at the start
# of a logical line there).
properties_check() { # <file> <shown name>
  local LC_ALL=C
  local status=2 content="" line logical="" start=0 number=0 continuing=false backslashes
  # read stops at a NUL byte (status 0), which Java reads and bash can't; at the end otherwise (1)
  { IFS= read -r -d '' content; status=$?; } 2> /dev/null < "$1" || true
  case $status in
    0) theme_problems+=("$2: a NUL byte, which Java reads and this check can't: refused"); return ;;
    1) ;;
    *) theme_problems+=("$2: can't be read: refused"); return ;;
  esac
  content=${content//$'\r\n'/$'\n'}
  content=${content//$'\r'/$'\n'}
  # the empty line after the last one ends a continuation there, as the end of the file does for Java
  while IFS= read -r line; do
    number=$((number + 1))
    if [[ $line == *[![:print:]$'\t\f']* ]]; then
      theme_problems+=("$2:$number: a byte outside printable ASCII, which Keycloak may decode otherwise than this check reads it (write such a character \\uXXXX): refused")
      return
    fi
    line=${line#"${line%%[!$' \t\f']*}"}
    if ! $continuing || [ -z "$logical" ]; then
      [ -n "$line" ] || continue
      case $line in '#'* | '!'*) continue ;; esac
      start=$number
      logical=""
    fi
    backslashes=${line##*[!\\]}
    if [ $(( ${#backslashes} % 2 )) -eq 1 ]; then
      logical+=${line%\\}
      continuing=true
      continue
    fi
    logical+=$line
    continuing=false
    # without an escape, the line as it is; with one, decoded
    decoded=$logical
    [[ $logical != *\\* ]] || properties_decode "$logical"
    if [[ $decoded == *'${'* ]]; then
      theme_problems+=("$2:$start: '\${' is resolved by Keycloak from its environment and Java's system properties, and the theme's pages show the values: refused")
    fi
  done <<< "$content"$'\n'
}

theme_problems=()
not_assigned=()
# What a realm export may hold (intent 0013): a client profile whose client-id-metadata-document
# executor allows the http scheme, or permits any domain, would let Keycloak fetch any URL an
# unauthenticated client names, on every application's network it is attached to (intent 0007).
# Keycloak reads the http setting as Jackson does ("True", "TRUE", " true" and 1 are true): only
# false is accepted. It permits a host equal to a domain, or ending with what follows "*." (Keycloak
# 26.8.1, tests/0013-keycloak-facts.sh): "*." matches every host written with a final dot; "*" is
# refused as well (PA-7). It refuses a domain list that isn't a list.
realm_problems=()
cimd_problems() { # <realm file>: one line per problem, "<profile>: …" (on its stdin: jq may be a Windows
  # program, which MSYS_NO_PATHCONV leaves with a path of Git Bash)
  jq -r '.clientProfiles.profiles[]? | .name as $profile | .executors[]?
    | select(.executor == "client-id-metadata-document") | (.configuration // {}) as $c
    | (($c["cimd-allow-http-scheme"] // false) as $http
        | if $http == false or $http == "false" then empty
          else "client profile \($profile): its client-id-metadata-document executor allows the http scheme (cimd-allow-http-scheme: \($http | tojson); false only)" end),
      ($c["cimd-allow-permitted-domains"] // [] | arrays | .[] | select(. == "*" or . == "*.")
        | "client profile \($profile): its client-id-metadata-document executor permits the domain \"\(.)\"")' < "$1"
}
for file in "${realms[@]}"; do
  name=$(basename "$file")
  realm=${name%-realm.json}
  if [ "$realm" = "$name" ] || [ -z "$realm" ]; then
    not_assigned+=("--realm $file: a realm export is named <realm>-realm.json, after the realm it holds")
  elif ! in_entry "$realm" "$REG_REALMS"; then
    not_assigned+=("--realm $file: realm $realm is not $app's (its registry entry's realms: ${REG_REALMS:-none})")
  elif ! command -v jq > /dev/null; then
    echo "register-app.sh needs jq to read a realm export (README.md, \"Development\"); nothing was registered." >&2
    exit 1
  elif ! found=$(cimd_problems "$file" 2> /dev/null); then
    realm_problems+=("--realm $file: not JSON that jq can read: refused")
  else
    while IFS= read -r problem; do
      [ -z "$problem" ] || realm_problems+=("--realm $file: $problem: Keycloak would fetch any URL, other applications' containers included: refused")
    done <<< "$found"
  fi
done
if [ -n "$themes" ]; then
  for dir in "$themes"/*/; do
    [ -d "$dir" ] || continue
    dir=${dir%/}
    name=${dir##*/}
    if ! in_entry "$name" "$REG_THEMES"; then
      not_assigned+=("--themes $themes: theme $name is not $app's (its registry entry's themes: ${REG_THEMES:-none})")
      continue
    fi
    # one walk: each link or special file (the theme's directory itself, when it is one: find doesn't
    # follow it), and each theme.properties, whatever its case; a walk find can't finish (a directory
    # it can't read, above) is refused, not taken as clean
    while IFS= read -r -d '' path; do
      if [ -L "$path" ] || [ ! -f "$path" ]; then
        theme_problems+=("--themes $themes: $name${path#"$dir"}: a symbolic link or a special file, whose target Keycloak would serve: refused")
      else
        properties_check "$path" "--themes $themes: $name${path#"$dir"}"
      fi
    done < <(find "$dir" \( ! -type f ! -type d -o -type f -iname theme.properties \) -print0)
    wait "$!" || theme_problems+=("--themes $themes: $name: find couldn't walk all of it (above): refused")
  done
fi
if [ -n "$rabbitmq_user" ] && [ "$rabbitmq_user" != "$REG_RABBITMQ_USER" ]; then
  not_assigned+=("--rabbitmq-user $rabbitmq_user: not $app's RabbitMQ user (its registry entry's: ${REG_RABBITMQ_USER:-none})")
fi
if [ ${#not_assigned[@]} -gt 0 ]; then
  printf '%s\n' "${not_assigned[@]}" >&2
  echo "A registration touches only what the application's entry in registry.txt assigns to it; nothing was registered." >&2
  exit 1
fi

if [ ${#theme_problems[@]} -gt 0 ]; then
  printf '%s\n' "${theme_problems[@]}" >&2
  echo "A theme holds nothing that would show the shared Keycloak's environment on its pages (README.md, \"What an application provides\"); nothing was registered." >&2
  exit 1
fi
if [ ${#realm_problems[@]} -gt 0 ]; then
  printf '%s\n' "${realm_problems[@]}" >&2
  echo "A realm's client policies fetch client metadata documents over https from named domains only (README.md, \"What an application provides\"); nothing was registered." >&2
  exit 1
fi

# The site, generated before anything changes too: a routes file that names a host or a port, or
# that the notation refuses, registers nothing
if [ -n "$proxy" ]; then
  if ! site=$(routes_generate "$proxy" "$INFRA_ENV"); then
    echo "The routes file $proxy is refused (above); nothing was registered." >&2
    exit 1
  fi
fi

# The registration account's credentials, read before anything changes too (account_login, below)
client_id=""
secret=""
if [ ${#realms[@]} -gt 0 ]; then
  stack_env_read client_id KC_REGISTRATION_CLIENT_ID
  stack_env_read secret KC_REGISTRATION_CLIENT_SECRET
fi

# The application's own network, c4-infra.<app> (intent 0007), once every check has passed: created
# when missing, the shared services it uses attached to it (never keycloak-db), compose.apps.yml
# written so that they stay attached when the stack is recreated. Its containers join it as an
# external network, never c4-infra.
bash "$INFRA_DIR/networks.sh" ensure "$app"

# Keycloak: the admin CLI inside the container, over the plain HTTP port of the Docker network, as
# the registration account (registration-account.sh's account_login, account and probe): a service
# account of the master realm that may create realms and manage the registry's, nothing else.
# Keycloak's administrators, the bootstrap one included, may be replaced or deleted: registrations
# don't use them. The account's secret, read from .env, reaches the CLI in its environment
# (KC_CLI_CLIENT_SECRET, passed by name); the CLI's session lives in the container's /dev/shm (memory
# only, mode 600), removed on exit.
if [ ${#realms[@]} -gt 0 ]; then
  # Every imported realm gets c4-infra's brute-force protection, whatever its export says (intent
  # 0010): a temporary lockout after 10 failures, 1 more minute per further failure, at most 15,
  # never for good (README.md, "Brute-force protection"; tests/0010-brute-force.sh). A realm already
  # in Keycloak keeps its own until it is imported again.
  brute_force=(-s bruteForceProtected=true -s permanentLockout=false -s maxTemporaryLockouts=0
    -s failureFactor=10 -s bruteForceStrategy=LINEAR -s waitIncrementSeconds=60
    -s maxFailureWaitSeconds=900 -s maxDeltaTimeSeconds=43200 -s quickLoginCheckMilliSeconds=1000
    -s minimumQuickLoginWaitSeconds=60)
  kc_session=$ACCOUNT_CONFIG
  if [ -z "$client_id" ] || ! account_login; then
    [ -z "${login_output:-}" ] || printf '%s\n' "$login_output" | tail -n 3 >&2
    echo "The registration account ${client_id:-(no KC_REGISTRATION_CLIENT_ID in .env)} doesn't log in to Keycloak: run up.sh in dev, the deployment on the demo host (registration-account.sh ensure creates it, and sets its secret to .env's); nothing was registered." >&2
    exit 1
  fi
  # What the account may do with each realm, before anything changes (probe: `get
  # realms/<realm>/roles`). A realm there but out of the account's reach stops the registration.
  declare -A realm_found=()
  for file in "${realms[@]}"; do
    realm=$(basename "$file" -realm.json)
    status=0
    probe "$realm" || status=$?
    case "$status" in
      0) realm_found[$realm]=true ;;
      1) realm_found[$realm]=false ;;
      2)
        echo "Realm $realm is in Keycloak, but the registration account $client_id may not manage it (created outside the registrations, and never granted to it): nothing was registered. registration-account.sh ensure grants it the realms of the registry that exist (up.sh in dev, the deployment on the demo host)." >&2
        exit 1
        ;;
      *)
        # Keycloak's last lines are above (probe)
        echo "Realm $realm: unexpected answer of Keycloak (above); nothing was registered." >&2
        exit 1
        ;;
    esac
  done
  for file in "${realms[@]}"; do
    realm=$(basename "$file" -realm.json)
    if ${realm_found[$realm]}; then
      if $reset_realms; then
        echo "Deleting realm $realm"
        account delete "realms/$realm"
      else
        echo "Realm $realm: already in Keycloak, left as it is"
        continue
      fi
    fi
    echo "Importing realm $realm"
    # on stdin: nothing to copy into the container, whatever the file's owner and mode; under the
    # file's name, the realm of the entry checked above, whatever its "realm" field says
    account -i create realms -f - -s "realm=$realm" "${brute_force[@]}" < "$file"
    echo "Realm $realm: brute-force protection set (README.md, \"Brute-force protection\")"
  done
fi

# Themes: copied into the directory Keycloak reads (mounted as a whole: a new theme shows in the
# running container too). In dev, Keycloak caches no theme (compose.dev.yml): the next page load
# shows the change, and the Keycloak every application uses isn't restarted. On the demo host it
# caches them: a changed theme restarts it, once per registration; an unchanged one restarts nothing.
if [ -n "$themes" ]; then
  changed=false
  for dir in "$themes"/*/; do
    [ -d "$dir" ] || continue
    name=$(basename "$dir")
    target="$INFRA_DIR/keycloak/themes/$name"
    if [ ! -d "$target" ] || ! diff -r "$dir" "$target" > /dev/null 2>&1; then
      rm -rf "$target"
      cp -r "$dir" "$target"
      own "$target"
      changed=true
      if [ "$INFRA_ENV" = dev ]; then
        echo "Theme $name installed: reload the login page (Keycloak doesn't cache themes in dev)"
      else
        echo "Theme $name installed"
      fi
    fi
  done
  if $changed && [ "$INFRA_ENV" = demo ]; then
    echo "Restarting Keycloak to load the themes"
    docker restart "$KEYCLOAK" > /dev/null
  fi
fi

# RabbitMQ: a virtual host per application, and its user. Imported as definitions (created, or
# updated in place: permissions, connections and the other applications are left alone), with
# the password as a salted SHA-256 hash, RabbitMQ's own format. rabbitmqctl doesn't read them from
# its standard input: the file goes into the container first.
if [ -n "$rabbitmq_user" ]; then
  # removed on exit (cleanup)
  work=$(mktemp -d)
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

# Reverse proxy: the application's site, generated above, checked by Caddy before it is kept (and
# left alone, with no reload, when it hasn't changed). Caddy is validated and reloaded, never
# restarted nor recreated: it keeps the rules of the INFRA_ENV it was started with.
if [ -n "$proxy" ]; then
  target="$INFRA_DIR/caddy/apps/$app.caddy"
  check=(caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile)
  reload=(caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile)
  # The previous site back, or none if there was none (the next run installs the new one again
  # rather than finding it "unchanged"), then Caddy's last lines and <message>, and a failed exit
  restore_site() { # <message>
    if $had_previous; then cp "$backup" "$target"; else rm -f "$target"; fi
    rm -f "$backup"
    printf '%s\n' "$output" | tail -n 3 >&2
    echo "$1" >&2
    exit 1
  }
  if [ -f "$target" ] && printf '%s\n' "$site" | cmp -s - "$target"; then
    echo "Reverse proxy: $app site unchanged"
  else
    backup=$(mktemp)
    had_previous=false
    if [ -f "$target" ]; then
      cp "$target" "$backup"
      had_previous=true
    fi
    printf '%s\n' "$site" > "$target"
    own "$target"
    output=$(docker exec "$REVERSE_PROXY" "${check[@]}" 2>&1) \
      || restore_site "The site generated from $proxy is invalid: the reverse proxy keeps its previous configuration"
    output=$(docker exec "$REVERSE_PROXY" "${reload[@]}" 2>&1) \
      || restore_site "The reverse proxy could not reload: the site of $proxy is not installed"
    rm -f "$backup"
    write_index
    echo "Reverse proxy: $app site installed (INFRA_ENV=$INFRA_ENV)"
  fi
fi
