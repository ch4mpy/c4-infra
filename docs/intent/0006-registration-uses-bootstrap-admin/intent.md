# Intent: Registrations depend on Keycloak's temporary bootstrap administrator

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: bug
- Source: conversation (review of the shared stack, 2026-10-21)
- Spec needed: yes
- Status: delivered
- Opened: 2026-10-21
- Decided: 2026-10-21
- Delivered: 2026-10-23 (deployed with 0697208; PR #6)
- Supersedes: —

## Problem

`register-app.sh` logs into the shared Keycloak as the bootstrap administrator (`KC_BOOTSTRAP_ADMIN_*` in `.env`, the `KC_ADMIN_PASSWORD` secret on the demo host). Keycloak creates that account on its very first start only, flags it as temporary, and its console invites the operator to replace it.

- Following that invitation (a permanent administrator, the temporary one deleted), or changing its password in the console, makes every later registration fail: each application's deployment stops at its Keycloak step.
- Rotating the `KC_ADMIN_PASSWORD` secret has no effect on Keycloak (read on first start only) but breaks the registrations the same way.

Today the README only warns not to do it.

## Proposed outcome

Registrations keep working whatever the operator does with the console's administrators, and the credential they use can be rotated. Success criterion: after the temporary administrator is replaced by a permanent one and deleted, an application's registration still imports its realm; after a rotation of the registration credential, the next deployment works.

## Affected users and systems

- Demo operator, Developer, Application.
- Registration, dev and demo stacks (Keycloak's master realm), deployment workflow (secrets).

## Constraints

- The credential stays off command lines and out of the repository.

## Open questions

- *Suggested solution*: a dedicated service account in the master realm, created once, for registrations only — to be settled in the spec.
