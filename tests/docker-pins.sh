#!/usr/bin/env bash
# The repositories of the images c4-infra builds itself, one per line: the stack's Keycloak and
# reverse proxy (up.sh), the tests' stand-in host and probe (tests/lib/stand-in-host.sh). The
# preflight's reaper removes the images of these repositories a pull or a rebuild replaced
# (tests/lib/docker-preflight.sh, docker_preflight --pins); never a shared repository's (postgres,
# alpine, caddy…), whose digest references may be another project's.
#
#   bash tests/docker-pins.sh
printf '%s\n' c4-infra/keycloak c4-infra/reverse-proxy c4-infra/stand-in-host c4-test/probe
