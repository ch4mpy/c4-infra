#!/usr/bin/env bash
# An application's routes file, turned into its Caddy site (README.md, "Routes file"). Sourced by
# register-app.sh, and a command:
#
#   bash routes.sh generate <routes file> <app> <dev|demo>
#       prints <app>'s site: its host name in that environment (the registry's dev-host or
#       demo-host), and each route's upstream (registry.sh's registry_upstream); each problem of the
#       file goes to stderr as "<file>:<line>: …", exit 1; exit 2 when the registry is invalid or
#       <app> isn't in it
#
# Function, once sourced (after registry.sh):
#
#   routes_generate <routes file> <dev|demo>   prints the site of the entry registry_entry set;
#                                              returns 1, each problem on stderr, when the file is
#                                              refused
#
# The notation, one route per line, '#' starting a comment:
#
#   <path>  <target>  [<option>...]
#     path:    /exact  |  /prefix/*  |  ~<regular expression>
#              (characters: A-Z a-z 0-9 . _ ~ / -, and for a regex ^ $ * + ? ( ) | [ ])
#     target:  gateway | mcp | fr | en | ui | redirect
#     options: to=<path>          redirect only, required: a path on the same host
#              max-body=<n>KB|MB  request body limit (413 beyond)
#              prefix=<path>      prepended to the request's path before proxying
#
# Routes are tried in the file's order and the first match serves the request; a /<p>/* route also
# redirects /<p> to /<p>/ (301); any other path answers 404. A routes file names neither a host, a
# scheme nor a port: the registry gives each role's upstream, per environment.

_ROUTES_EXACT='^/[A-Za-z0-9._~/-]*$'
_ROUTES_PREFIX='^/([A-Za-z0-9._~/-]*/)?[*]$'
_ROUTES_REGEX='^~[]A-Za-z0-9._~/^$*+?()|[-]+$'
_ROUTES_TO='^/[A-Za-z0-9._~/-]*$'
_ROUTES_PREFIX_OPTION='^/([A-Za-z0-9._~/-]*[A-Za-z0-9._~-])?$'
_ROUTES_SIZE='^[1-9][0-9]*(KB|MB)$'

# Whether a token names a host, a scheme or a port: "://", "<name>:<digits>", a path starting with
# "//" (another host), or a dotted name where a target or a path is expected
_routes_names_host() { # <token> <path|target|option>
  local token=$1 value=${1#*=}
  local port='[A-Za-z0-9]:[0-9]+'
  [[ $token == *://* ]] && return 0
  [[ $token =~ $port ]] && return 0
  case "$2" in
    path) [[ $token == //* ]] || { [[ $token != /* && $token != '~'* && $token == *.* ]]; } ;;
    target) [[ $token == *.* ]] ;;
    option) [[ $value == //* ]] ;;
    *) return 1 ;;
  esac
}

# Runs in routes_generate's scope (bash's dynamic scoping): its `name`, `number` and `problems`
_routes_problem() {
  echo "$name:$number: $1" >&2
  problems=$((problems + 1))
}

# A reverse_proxy to <upstream>, indented by <indent>: an HTTPS upstream (dev's gateway and MCP
# server) is verified against the local CA, and gets the client's Host (Caddy otherwise sends the
# upstream's own host to an HTTPS upstream)
_routes_proxy() { # <upstream> <indent>
  local upstream=$1 i=$2 server
  if [[ $upstream == https://* ]]; then
    server=${upstream#https://}
    server=${server%%[:/]*}
    printf '%sreverse_proxy %s {\n' "$i" "$upstream"
    printf '%s\theader_up Host {hostport}\n' "$i"
    printf '%s\ttransport http {\n' "$i"
    printf '%s\t\ttls_server_name %s\n' "$i" "$server"
    printf '%s\t\ttls_trust_pool file /certs/ca.crt\n' "$i"
    printf '%s\t}\n' "$i"
    printf '%s}\n' "$i"
  else
    printf '%sreverse_proxy %s\n' "$i" "$upstream"
  fi
}

routes_generate() { # <routes file> <dev|demo>
  local file=$1 env=$2 name number=0 problems=0 line host path target option key value upstream
  local i k p
  local -a tokens paths=() targets=() tos=() bodies=() prefixes=() upstreams=()
  local -A seen_options exact=()
  case "$env" in
    dev) host=$REG_DEV_HOST ;;
    demo) host=$REG_DEMO_HOST ;;
    *)
      echo "Unknown environment '$env' (dev or demo)" >&2
      return 1
      ;;
  esac
  if [ ! -f "$file" ]; then
    echo "The routes file $file is missing" >&2
    return 1
  fi
  name=$(basename "$file")

  while IFS= read -r line || [ -n "$line" ]; do
    number=$((number + 1))
    line=${line%$'\r'}
    line=${line%%#*}
    read -r -a tokens <<< "$line"
    [ ${#tokens[@]} -gt 0 ] || continue
    path=${tokens[0]}
    target=${tokens[1]:-}
    if [ -z "$target" ]; then
      _routes_problem "a route is '<path> <target> [<option>...]', not '$path' alone"
      continue
    fi

    # a host, a scheme or a port, wherever it is
    if _routes_names_host "$path" path; then
      _routes_problem "routes name neither a host nor a port: '$path'"
      continue
    fi
    if _routes_names_host "$target" target; then
      _routes_problem "routes name neither a host nor a port: '$target'"
      continue
    fi
    for option in "${tokens[@]:2}"; do
      if _routes_names_host "$option" option; then
        _routes_problem "routes name neither a host nor a port: '$option'"
        continue 2
      fi
    done

    if ! [[ $path =~ $_ROUTES_EXACT || $path =~ $_ROUTES_PREFIX || $path =~ $_ROUTES_REGEX ]]; then
      _routes_problem "path '$path' is not /exact, /prefix/* nor ~<regular expression>, of the characters A-Z a-z 0-9 . _ ~ / - (and ^ \$ * + ? ( ) | [ ] in a regular expression)"
      continue
    fi
    case "$target" in
      gateway | mcp | fr | en | ui | redirect) ;;
      *)
        _routes_problem "unknown target '$target' (gateway, mcp, fr, en, ui or redirect)"
        continue
        ;;
    esac

    local to='' body='' prefix=''
    seen_options=()
    for option in "${tokens[@]:2}"; do
      key=${option%%=*}
      value=${option#*=}
      if [ "$key" = "$option" ] || [ -n "${seen_options[$key]:-}" ]; then
        if [ -n "${seen_options[$key]:-}" ]; then
          _routes_problem "$key= given twice"
        else
          _routes_problem "unknown option '$option' (to=, max-body= or prefix=)"
        fi
        continue 2
      fi
      seen_options[$key]=1
      case "$key" in
        to)
          if [ "$target" != redirect ]; then
            _routes_problem "to= is for a redirect only, not for the role $target"
            continue 2
          fi
          [[ $value =~ $_ROUTES_TO ]] || { _routes_problem "to= takes a path on the same host, not '$value'"; continue 2; }
          to=$value
          ;;
        max-body)
          if [ "$target" = redirect ]; then
            _routes_problem "max-body= is for a role, not for a redirect"
            continue 2
          fi
          [[ $value =~ $_ROUTES_SIZE ]] || { _routes_problem "max-body= takes <n>KB or <n>MB, not '$value'"; continue 2; }
          body=$value
          ;;
        prefix)
          if [ "$target" = redirect ]; then
            _routes_problem "prefix= is for a role, not for a redirect"
            continue 2
          fi
          [[ $value =~ $_ROUTES_PREFIX_OPTION ]] \
            || { _routes_problem "prefix= takes a path without a final '/', not '$value'"; continue 2; }
          prefix=$value
          ;;
        *)
          _routes_problem "unknown option '$option' (to=, max-body= or prefix=)"
          continue 2
          ;;
      esac
    done
    if [ "$target" = redirect ] && [ -z "$to" ]; then
      _routes_problem "redirect needs to=<path>"
      continue
    fi

    upstream=''
    if [ "$target" != redirect ]; then
      if ! upstream=$(registry_upstream "$target" "$env" 2>&1); then
        _routes_problem "$upstream"
        continue
      fi
    fi
    paths+=("$path")
    targets+=("$target")
    tos+=("$to")
    bodies+=("$body")
    prefixes+=("$prefix")
    upstreams+=("$upstream")
    [[ $path == '~'* || $path == *'*' ]] || exact[$path]=1
  done < "$file"

  if [ "$problems" -eq 0 ] && [ ${#paths[@]} -eq 0 ]; then
    echo "$name: no route" >&2
    problems=1
  fi
  [ "$problems" -eq 0 ] || return 1

  echo "# Generated by c4-infra's register-app.sh from $REG_APP's routes file and registry entry (INFRA_ENV=$env): don't edit"
  echo "$host {"
  printf '\timport site\n'
  for i in "${!paths[@]}"; do
    path=${paths[$i]}
    [[ $path == '~'* ]] || continue
    printf '\t@route%d path_regexp "%s"\n' "$((i + 1))" "${path#\~}"
  done
  printf '\troute {\n'
  for i in "${!paths[@]}"; do
    path=${paths[$i]}
    target=${targets[$i]}
    if [[ $path == '~'* ]]; then
      printf '\t\thandle @route%d {\n' "$((i + 1))"
    else
      printf '\t\thandle %s {\n' "$path"
    fi
    if [ "$target" = redirect ]; then
      printf '\t\t\tredir * %s temporary\n' "${tos[$i]}"
    else
      case "$target" in
        fr | en | ui) printf '\t\t\timport spa-headers\n' ;;
      esac
      if [ -n "${bodies[$i]}" ]; then
        printf '\t\t\trequest_body {\n\t\t\t\tmax_size %s\n\t\t\t}\n' "${bodies[$i]}"
      fi
      if [ -n "${prefixes[$i]}" ]; then
        printf '\t\t\trewrite * %s{uri}\n' "${prefixes[$i]}"
      fi
      _routes_proxy "${upstreams[$i]}" $'\t\t\t'
    fi
    printf '\t\t}\n'
  done
  # /<p> → /<p>/, for each /<p>/* route without a route of its own for /<p>
  local -A redirected=()
  for path in "${paths[@]}"; do
    [[ $path == /*/'*' ]] || continue
    p=${path%/\*}
    [ -z "${exact[$p]:-}" ] && [ -z "${redirected[$p]:-}" ] || continue
    redirected[$p]=1
    printf '\t\thandle %s {\n\t\t\tredir * %s/ permanent\n\t\t}\n' "$p" "$p"
  done
  printf '\t\thandle {\n\t\t\trespond 404\n\t\t}\n'
  printf '\t}\n'
  echo "}"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -euo pipefail
  source "$(cd "$(dirname "$0")" && pwd)/registry.sh"
  if [ "${1:-}" != generate ] || [ $# -ne 4 ]; then
    echo "Usage: bash $0 generate <routes file> <app> <dev|demo>" >&2
    exit 1
  fi
  registry_check || exit 2
  registry_entry "$3" || exit 2
  routes_generate "$2" "$4" || exit 1
fi
