# Intent: A deployment that pulls a new database image recreates the database under a running Keycloak, and the registration check then blames the administrator

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: bug
- Source: conversation (the milestone push of 0023 and 0020, 2026-10-28; deploy-demo run 40636936869)
- Spec needed: no
- Status: planned
- Opened: 2026-10-28
- Decided: 2026-10-28
- Supersedes: —
- Mode: bootstrap

## Problem

`postgres:18.6` was published again upstream under the same tag (its digest `sha256:bc8d7bdd…` on Docker Hub, `sha256:edb0c08d…` before). The demo deployment of 2026-10-28 05:15 UTC pulled it and recreated `c4-infra.keycloak-db` while `c4-infra.keycloak` kept running: `demo/deploy.sh` stops Keycloak first only when Keycloak's own image changes (`:38-41`). Right after, `registration-account.sh ensure` could log in neither as the registration account nor as the bootstrap administrator, and the deployment failed:

- Steps: a demo deployment while the database's image changes under the same tag.
- Expected: the database replaced without Keycloak losing it, then the registration check passing; or, when Keycloak doesn't answer, a message that says so.
- Observed: `Container c4-infra.keycloak-db Recreate`, `Container c4-infra.keycloak Running`, then "No administrator of Keycloak's master realm could log in to create the registration account c4-infra-registration, or set its secret to .env's: the bootstrap administrator of .env no longer works (replaced, or its password changed)", exit 1. The deployment before it (03:24 UTC) passed with the same code.
- Environment: the demo host (`infra.c4-soft.com`), run 40636936869 on `main` `f442263`; the stack stayed up and healthy.

Any upstream rebuild of the database's image (or of another image under its tag) can fail a deployment that changes nothing, and the message sends the operator after an administrator's password that is fine.

## Proposed outcome

A deployment that replaces the database's image leaves Keycloak working with the new database before anything checks Keycloak, and passes. The registration check tells a Keycloak that doesn't answer (yet) from an account or an administrator that doesn't work.

## Affected users and systems

- Personas: Demo operator (reads the failed deployment); Application (registrations on the demo host)
- Modules / systems: demo host (`demo/deploy.sh`), registration (`registration-account.sh`)

## Constraints

- No deployment loses Keycloak's data; the dump taken before a Keycloak upgrade (0013) still comes first when Keycloak's image changes.

## Open questions

- Whether the stack's images are pinned by digest, so that an upstream rebuild changes nothing until the stack chooses it — the plan (a product owner's choice if it changes how upgrades come).
- Whether the rerun of run 40636936869 passes (the transient cause confirmed) — the product owner's rerun.
