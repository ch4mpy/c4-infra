#!/usr/bin/env bash
# The images c4-infra pins, one reference per line, read where they are pinned: the stack's compose
# files, keycloak-image.properties, the Dockerfiles of the images the stack and the tests build, the
# images the tests run, and the images built here. The preflight's reaper removes the images of these
# repositories a pull replaced (tests/lib/docker-preflight.sh, docker_preflight --pins). A file missing
# (a copy of the suite without the stack) gives nothing.
#
#   bash tests/docker-pins.sh
set -uo pipefail
cd "$(dirname "$0")/.."

{
  sed -n 's/^[[:space:]]*image:[[:space:]]*//p' compose*.yml 2> /dev/null | grep -v '\$'
  if [ -f keycloak-image.properties ]; then
    sed -n 's/^KC_VERSION=\(.*\)/quay.io\/keycloak\/keycloak:\1/p; s/^KC_PUBLISHED_IMAGE=//p' keycloak-image.properties
  fi
  caddy=$(sed -n 's/^ARG CADDY_VERSION=//p' reverse-proxy/Dockerfile 2> /dev/null | tr -d '\r')
  [ -z "$caddy" ] || printf 'caddy:%s-alpine\ncaddy:%s-builder-alpine\n' "$caddy" "$caddy"
  find tests -name Dockerfile -exec sed -n 's/^FROM[[:space:]]*\([^[:space:]]*\).*/\1/p' {} + 2> /dev/null | grep -v '\$'
  grep -hoE '(^|[^A-Za-z0-9_./-])(alpine:3|bash:5\.2|caddy:[0-9.]+-alpine|postgres:[0-9.]+)([^A-Za-z0-9_.-]|$)' \
    tests/*.sh tests/lib/*.sh 2> /dev/null | sed -E 's/^[^a-z]//; s/[^A-Za-z0-9_.:-]$//'
  printf '%s\n' c4-infra/keycloak c4-infra/reverse-proxy c4-infra/stand-in-host c4-test/probe
} | tr -d '\r' | sed '/^$/d' | LC_ALL=C sort -u
