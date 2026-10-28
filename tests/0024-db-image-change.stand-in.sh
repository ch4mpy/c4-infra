#!/usr/bin/env bash
# 0024: a demo deployment that recreates Keycloak's database (its image changed under the same tag, as
# postgres:18.6 did upstream on 2026-10-28) restarts Keycloak on it, and passes; the registration check
# tells a Keycloak that doesn't answer from an account or an administrator that doesn't work:
#
#   - a stand-in deployed by stand_in_accounts faito; then postgres:18.6 replaced in its Docker by an
#     image built on it (a label), and demo/deploy.sh run again as c4-infra, as the workflow does: it
#     exits 0, the registration account up to date and not repaired, Keycloak started after its
#     database, the master realm's discovery answering;
#   - Keycloak's database stopped under a running Keycloak: registration-account.sh ensure fails,
#     saying Keycloak doesn't answer, not that an administrator doesn't log in.
#
#   bash tests/0024-db-image-change.stand-in.sh
#
# The test's postgres:18.6 is removed at the end: the stand-in's next deployment pulls the real one.
#
# covers: demo/ registration-account.sh compose.yml compose.demo.yml tests/stand-in-host/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/stand-in-host.sh

STACK=/home/c4-infra/c4-infra
trap 'stand_in_exec docker image rm -f postgres:18.6 > /dev/null 2>&1; stand_in_down' EXIT

started() { # <container>: when it last started
  stand_in_exec docker inspect -f '{{.State.StartedAt}}' "$1" | tr -d '\r'
}

new_database_image() {
  stand_in_exec sh -c "printf 'FROM postgres:18.6\nLABEL c4-infra.test=0024\n' | docker build -q -t postgres:18.6 - > /dev/null"
}

deploys() { # demo/deploy.sh again, as the workflow runs it; its output in /home/c4-infra/deploy-0024.log
  stand_in_ssh c4-infra "cd ~/c4-infra && bash ./demo/deploy.sh < /dev/null > ~/deploy-0024.log 2>&1" \
    || { stand_in_exec tail -n 15 /home/c4-infra/deploy-0024.log; return 1; }
}

said() { # <text>: the redeployment's output holds it
  stand_in_exec grep -qF -- "$1" /home/c4-infra/deploy-0024.log || { stand_in_exec tail -n 15 /home/c4-infra/deploy-0024.log; return 1; }
}

not_said() { # <text>
  ! stand_in_exec grep -nF -- "$1" /home/c4-infra/deploy-0024.log
}

keycloak_after_its_database() {
  local database keycloak
  database=$(started c4-infra.keycloak-db)
  keycloak=$(started c4-infra.keycloak)
  [[ $keycloak > $database ]] || { echo "Keycloak started $keycloak, its database $database"; return 1; }
}

discovery_answers() {
  stand_in_exec docker exec c4-infra.reverse-proxy wget -qO- http://keycloak:8080/auth/realms/master/.well-known/openid-configuration \
    | grep -q '"issuer"'
}

check "the stand-in host starts" stand_in_up
check "the accounts (c4-infra, faito), the shared stack deployed as c4-infra" stand_in_accounts faito
database_before=$(started c4-infra.keycloak-db)
check "postgres:18.6 replaced in the stand-in's Docker (an image built on it)" new_database_image
check "the deployment runs again and exits 0" deploys
check "it recreated Keycloak's database" test "$(started c4-infra.keycloak-db)" != "$database_before"
check "Keycloak started after its database" keycloak_after_its_database
check "the registration account is up to date" said "Registration account c4-infra-registration: up to date"
check "and wasn't repaired: its login didn't fail" not_said "its secret set to .env's"
check "the master realm's discovery answers" discovery_answers

# Keycloak's database stopped under a running Keycloak: no answer, which no administrator could fix
stand_in_exec docker stop c4-infra.keycloak-db > /dev/null
stand_in_ssh c4-infra "cd ~/c4-infra && bash ./registration-account.sh ensure < /dev/null > ~/ensure-0024.log 2>&1"
status=$?
ensure_said() { stand_in_exec grep -qF -- "$1" /home/c4-infra/ensure-0024.log || { stand_in_exec tail -n 8 /home/c4-infra/ensure-0024.log; return 1; }; }
ensure_not_said() { ! stand_in_exec grep -nF -- "$1" /home/c4-infra/ensure-0024.log; }
check "its database stopped: registration-account.sh ensure fails" test "$status" -ne 0
check "saying Keycloak doesn't answer" ensure_said "Keycloak doesn't answer"
check "not that an administrator doesn't log in" ensure_not_said "No administrator of Keycloak's master realm could log in"
check "nor that the account was repaired" ensure_not_said "its secret set to .env's"
finish
