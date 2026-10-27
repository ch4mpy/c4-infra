#!/usr/bin/env bash
# The application registry, registry.txt (its header says what each column holds). Sourced by
# register-app.sh, and a command:
#
#   bash registry.sh check                              nothing on stdout, each problem on stderr;
#                                                       exit 0 when valid, 1 otherwise
#   bash registry.sh next                               the smallest number no entry has (1 to 38);
#                                                       exit 1 when every one is taken
#   bash registry.sh entry <app>                        the entry, one key=value per line: n, prefix,
#                                                       app, realms, rabbitmq_user, themes, dev_host,
#                                                       demo_host (lists comma-separated, empty for
#                                                       "-"); exit 1 when <app> isn't in the
#                                                       registry, 2 when the registry is invalid
#   bash registry.sh upstream <app> <role> <dev|demo>   the URL the reverse proxy routes <role> to
#                                                       (gateway, mcp, fr, en, ui); exit 1 for an
#                                                       unknown application or role (or an invalid
#                                                       registry), 2 when the role has no upstream
#                                                       in that environment
#
# Data on stdout, messages on stderr: the skills read this output (create-dev-infra).
#
# Functions, once sourced:
#
#   registry_check             the problems of the registry, as `check`; returns 1 when there is one
#                              (among them, an entry claiming Keycloak's master realm, a theme built
#                              into Keycloak, or RabbitMQ's administrator, RABBITMQ_ADMIN_USER)
#   registry_entry <app>       sets REG_N REG_APP REG_REALMS REG_RABBITMQ_USER REG_THEMES REG_DEV_HOST
#                              REG_DEMO_HOST (lists as in the file, empty for "-"); returns 1, saying
#                              how to register, when <app> isn't in the registry
#   registry_next              prints the next free number; returns 1 when 1 to 38 are all taken
#   registry_upstream <role> <dev|demo>   prints the upstream of <role> for the entry registry_entry set
#   dotenv_value <file> <key>  prints KEY's value in a .env file, as compose reads it (below): the one
#                              .env reader of c4-infra's scripts (demo/c4-app included)
#   stack_env_read <var> <key>
#                              dotenv_value of the stack's .env (next to this script) into the
#                              variable <var>; a value the reader refuses stops the script (exit 1),
#                              naming the key: for a script that needs the value
#
# REGISTRY_FILE (default: registry.txt next to this script) is a test seam only: on the demo host,
# registrations run through a root-owned command that clears the environment (intent 0002).

REGISTRY_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REGISTRY_FILE=${REGISTRY_FILE:-$REGISTRY_DIR/registry.txt}

# The shared stack's own names (its services, and the stack itself): an application can't take one
REGISTRY_RESERVED=(c4-infra keycloak keycloak-db keycloak-import mailpit rabbitmq grafana-lgtm reverse-proxy)
REGISTRY_MAX=38
# The themes built into Keycloak 26 (its theme jars' META-INF/keycloak-themes.json): a registered
# theme directory of that name would replace it for every realm, master included. The dotted ones
# are outside a theme name's characters already; listed for the next image that adds one.
REGISTRY_KEYCLOAK_THEMES=(base keycloak keycloak.v2 keycloak.v3)

# What the shared stack itself owns in Keycloak and RabbitMQ, which no entry may claim: a
# registration may delete and import its entry's realms and set its RabbitMQ user's password
# (intent 0002), so an entry owning the master realm or the broker's administrator would hand
# them to that application. The administrator is RABBITMQ_ADMIN_USER of the .env next to this
# script (read as data), admin by default.
_registry_rabbitmq_admin() {
  local user
  user=$(dotenv_value "$REGISTRY_DIR/.env" RABBITMQ_ADMIN_USER) || return 1
  printf '%s' "${user:-admin}"
}

# The value of KEY in a .env file, read as data the way compose reads it (measured with compose
# 2.40): its last definition (KEY=, export KEY=, spaces around "=" allowed), leading spaces and a
# Windows line end removed; single quotes keep what is between them (\' is a quote); in double
# quotes and unquoted, "$$" is a "$"; an unquoted value ends at " #" and loses its final spaces.
# What compose would read otherwise is refused, saying why, rather than read differently (returns
# 1): a "$" it interpolates ($NAME, ${NAME}), an escape sequence in double quotes, a quote that
# doesn't close. Prints nothing (returns 0) when the file or the key is missing.
dotenv_value() { # <file> <key>
  local file=$1 key=$2 line value
  local single="^'((\\\\.|[^\\\\'])*)'" double='^"((\\.|[^\\"])*)"'
  [ -f "$file" ] || return 0
  line=$(grep -E "^[[:space:]]*(export[[:space:]]+)?$key[[:space:]]*=" "$file" | tail -n 1) || true
  [ -n "$line" ] || return 0
  value=${line#*=}
  value=${value%$'\r'}
  value=${value#"${value%%[![:space:]]*}"}
  if [[ $value =~ $single ]]; then
    value=${BASH_REMATCH[1]}
    printf '%s' "${value//\\\'/\'}"
    return 0
  elif [[ $value =~ $double ]]; then
    value=${BASH_REMATCH[1]}
    value=${value//\\\"/\"}
    if [[ $value == *\\* ]]; then
      echo "$file: $key: a backslash in double quotes, which compose reads as an escape sequence: refused (single quotes keep it as it is)" >&2
      return 1
    fi
  elif [[ $value == [\"\']* ]]; then
    echo "$file: $key: a quote that doesn't close: refused" >&2
    return 1
  else
    value=${value%% \#*}
    value=${value%"${value##*[![:space:]]}"}
  fi
  if [[ ${value//\$\$/} == *\$* ]]; then
    echo "$file: $key: compose interpolates its \$ (\$NAME, \${NAME}): refused (write \$\$ for a \$, or single quotes)" >&2
    return 1
  fi
  printf '%s' "${value//\$\$/\$}"
}

# KEY of the stack's .env into the variable <var>, read as data rather than sourced, as compose
# reads it (the demo's .env is written for compose: "$$" for a "$"); run in the caller's shell: a
# value the reader refuses stops the script there, saying so, rather than leaving <var> empty for
# the script to go on with (networks.sh, register-app.sh and registration-account.sh read .env
# before they change anything). A caller of dotenv_value itself must check its status: it is lost in
# a [ … ] argument, a prefix assignment or a function's argument, and set -e doesn't stop a function
# called in a condition.
stack_env_read() { # <var> <key>
  local _stack_env_read_value
  if ! _stack_env_read_value=$(dotenv_value "$REGISTRY_DIR/.env" "$2"); then
    echo "$(basename "$0"): $2 of $REGISTRY_DIR/.env is refused (above): stopped, rather than going on without it" >&2
    exit 1
  fi
  printf -v "$1" '%s' "$_stack_env_read_value"
}

# "<line number> <line>" for each entry of the registry: neither a comment nor a blank line, the
# \r of a line end edited on Windows removed
registry_lines() {
  local number=0 line skipped='^[[:space:]]*(#|$)'
  if [ ! -f "$REGISTRY_FILE" ]; then
    echo "The registry $REGISTRY_FILE is missing" >&2
    return 1
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    number=$((number + 1))
    line=${line%$'\r'}
    [[ $line =~ $skipped ]] && continue
    printf '%s %s\n' "$number" "$line"
  done < "$REGISTRY_FILE"
}

# Helpers of registry_check, which run in its scope (bash's dynamic scoping): its `file`, `problems`
# and `owner`
_registry_problem() { # <problem>: on stderr, counted
  echo "$1" >&2
  problems=$((problems + 1))
}
_registry_claim() { # <kind> <value> <app> <line>: a value two entries (or one entry twice) claim
  local key="$1 $2"
  if [ -n "${owner[$key]:-}" ]; then
    _registry_problem "$file: $1 $2: ${owner[$key]} and $3 (line $4)"
  else
    owner[$key]="$3 (line $4)"
  fi
}

registry_check() {
  local lines number fields problems=0 file
  local n app realms rabbitmq_user themes dev_host demo_host value kind reserved rabbitmq_admin
  local -a values list_values
  local -A owner=()
  rabbitmq_admin=$(_registry_rabbitmq_admin) || _registry_problem "RABBITMQ_ADMIN_USER of $REGISTRY_DIR/.env can't be read (above)"
  local name='^[a-z][a-z0-9-]*$'
  local list='^[a-z0-9][a-z0-9_-]*(,[a-z0-9][a-z0-9_-]*)*$'
  local single='^[a-z0-9][a-z0-9_-]*$'
  local host='^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$'
  file=$(basename "$REGISTRY_FILE")
  lines=$(registry_lines) || return 1

  while read -r number fields; do
    [ -n "$number" ] || continue
    read -r -a values <<< "$fields"
    if [ ${#values[@]} -ne 7 ]; then
      _registry_problem "$file:$number: ${#values[@]} columns, 7 expected (n app realms rabbitmq-user themes dev-host demo-host)"
      continue
    fi
    n=${values[0]} app=${values[1]} realms=${values[2]} rabbitmq_user=${values[3]}
    themes=${values[4]} dev_host=${values[5]} demo_host=${values[6]}

    # two digits at most before the comparison: no leading zero ("04" would be another 4), no overflow
    if ! [[ $n =~ ^[1-9][0-9]?$ ]] || [ "$n" -gt "$REGISTRY_MAX" ]; then
      _registry_problem "$file:$number: number '$n' is not between 1 and $REGISTRY_MAX"
    fi
    if [[ $app =~ $name ]]; then
      for reserved in "${REGISTRY_RESERVED[@]}"; do
        [ "$app" != "$reserved" ] \
          || _registry_problem "$file:$number: $app is reserved for the shared stack (its own name and its services')"
      done
    else
      _registry_problem "$file:$number: application name '$app' is not lowercase letters, digits and '-'"
    fi
    [ "$realms" = - ] || [[ $realms =~ $list ]] \
      || _registry_problem "$file:$number: realms '$realms' is not '-' nor a comma-separated list of lowercase letters, digits, '_' and '-'"
    [ "$rabbitmq_user" = - ] || [[ $rabbitmq_user =~ $single ]] \
      || _registry_problem "$file:$number: RabbitMQ user '$rabbitmq_user' is not '-' nor lowercase letters, digits, '_' and '-'"
    [ "$themes" = - ] || [[ $themes =~ $list ]] \
      || _registry_problem "$file:$number: themes '$themes' is not '-' nor a comma-separated list of lowercase letters, digits, '_' and '-'"
    for value in "$dev_host" "$demo_host"; do
      [[ $value =~ $host ]] \
        || _registry_problem "$file:$number: host name '$value' is not a host name (lowercase, with a domain)"
    done

    _registry_claim number "$n" "$app" "$number"
    _registry_claim application "$app" "$app" "$number"
    for kind in realm theme; do
      if [ "$kind" = realm ]; then value=$realms; else value=$themes; fi
      [ "$value" != - ] || continue
      IFS=, read -r -a list_values <<< "$value"
      for value in "${list_values[@]}"; do
        [ "$kind $value" != "realm master" ] \
          || _registry_problem "$file:$number: realm master is Keycloak's own (the shared stack's): no entry may claim it"
        if [ "$kind" = theme ]; then
          for reserved in "${REGISTRY_KEYCLOAK_THEMES[@]}"; do
            [ "$value" != "$reserved" ] \
              || _registry_problem "$file:$number: theme $value is built into Keycloak (every realm's): no entry may claim it"
          done
        fi
        _registry_claim "$kind" "$value" "$app" "$number"
      done
    done
    [ "$rabbitmq_user" != "$rabbitmq_admin" ] \
      || _registry_problem "$file:$number: RabbitMQ user $rabbitmq_user is the broker's administrator (RABBITMQ_ADMIN_USER, the shared stack's): no entry may claim it"
    [ "$rabbitmq_user" = - ] || _registry_claim "RabbitMQ user" "$rabbitmq_user" "$app" "$number"
    # one namespace for both columns: a demo host can't be another application's dev host; nor its
    # MCP origin, which no other entry may take either, as a host or as an application's name
    _registry_claim "host name" "$dev_host" "$app" "$number"
    _registry_claim "host name" "$demo_host" "$app" "$number"
    _registry_claim "host name" "$(registry_mcp_host "$dev_host")" "$app's MCP origin" "$number"
    _registry_claim "host name" "$(registry_mcp_host "$demo_host")" "$app's MCP origin" "$number"
    _registry_claim application "$app-mcp" "$app's MCP origin" "$number"
  done <<< "$lines"

  [ "$problems" -eq 0 ]
}

registry_entry() {
  local wanted=$1 lines number n app realms rabbitmq_user themes dev_host demo_host rest
  lines=$(registry_lines) || return 1
  while read -r number n app realms rabbitmq_user themes dev_host demo_host rest; do
    [ "$app" = "$wanted" ] || continue
    [ "$realms" != - ] || realms=
    [ "$rabbitmq_user" != - ] || rabbitmq_user=
    [ "$themes" != - ] || themes=
    REG_N=$n
    REG_APP=$app
    REG_REALMS=$realms
    REG_RABBITMQ_USER=$rabbitmq_user
    REG_THEMES=$themes
    REG_DEV_HOST=$dev_host
    REG_DEMO_HOST=$demo_host
    return 0
  done <<< "$lines"
  cat >&2 <<EOF
$wanted is not in the registry, $REGISTRY_FILE.
A new application takes the number \`bash registry.sh next\` prints, and adds its line to registry.txt
first, in a commit of its own (see the file's header), before anything registers.
EOF
  return 1
}

registry_next() {
  local lines number n rest candidate
  local -A taken=()
  lines=$(registry_lines) || return 1
  while read -r number n rest; do
    if [ -n "$n" ]; then taken[$n]=1; fi
  done <<< "$lines"
  for ((candidate = 1; candidate <= REGISTRY_MAX; candidate++)); do
    if [ -z "${taken[$candidate]:-}" ]; then
      echo "$candidate"
      return 0
    fi
  done
  echo "Every number from 1 to $REGISTRY_MAX is taken: no port block is left below 49152 (README.md, 'Port registry')" >&2
  return 1
}

# An application's MCP origin (intent 0013): the first label of its host name suffixed with -mcp,
# turu.c4-soft.com → turu-mcp.c4-soft.com (one label under the dev certificate's *.dev.localhost)
registry_mcp_host() { # <host name>
  printf '%s-mcp.%s\n' "${1%%.*}" "${1#*.}"
}

# The upstream of a role, for the entry registry_entry set: in dev the port of its block, on the
# demo host its container on the port the README fixes for that role
registry_upstream() {
  local role=$1 env=$2 prefix=$((10 + REG_N))
  case "$env" in
    dev | demo) ;;
    *)
      echo "Unknown environment '$env' (dev or demo)" >&2
      return 1
      ;;
  esac
  case "$env $role" in
    'dev gateway') echo "https://host.docker.internal:${prefix}080" ;;
    'dev mcp') echo "https://host.docker.internal:${prefix}280" ;;
    'dev fr' | 'dev ui') echo "http://host.docker.internal:${prefix}200" ;;
    'dev en') echo "http://host.docker.internal:${prefix}205" ;;
    'demo gateway') echo "http://$REG_APP.gateway:7080" ;;
    'demo fr' | 'demo ui' | 'demo en') echo "http://$REG_APP.frontend:80" ;;
    'demo mcp') echo "http://$REG_APP.mcp:9080" ;;
    *)
      echo "Unknown role '$role' (gateway, mcp, fr, en or ui)" >&2
      return 1
      ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -euo pipefail
  usage() {
    echo "Usage: bash $0 check | next | entry <app> | upstream <app> <role> <dev|demo>" >&2
    exit 1
  }
  case "${1:-}" in
    check)
      [ $# -eq 1 ] || usage
      registry_check || exit 1
      ;;
    next)
      [ $# -eq 1 ] || usage
      registry_next || exit 1
      ;;
    entry)
      [ $# -eq 2 ] || usage
      registry_check || exit 2
      registry_entry "$2" || exit 1
      printf '%s\n' "n=$REG_N" "prefix=$((10 + REG_N))" "app=$REG_APP" "realms=$REG_REALMS" \
        "rabbitmq_user=$REG_RABBITMQ_USER" "themes=$REG_THEMES" "dev_host=$REG_DEV_HOST" \
        "demo_host=$REG_DEMO_HOST"
      ;;
    upstream)
      [ $# -eq 4 ] || usage
      registry_check || exit 1
      registry_entry "$2" || exit 1
      registry_upstream "$3" "$4" || exit $?
      ;;
    *) usage ;;
  esac
fi
