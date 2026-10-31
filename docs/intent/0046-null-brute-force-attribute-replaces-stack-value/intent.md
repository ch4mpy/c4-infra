# Intent: A brute-force setting an export's attributes hold as null replaces the stack's value, while the registration names the stack's

- Author: Jérôme Wacongne (product owner, tech lead); drafted by the agent from the review of 0041 v3's diff
- Kind: bug
- Source: conversation (2026-10-30: the review of spec 0041 v3's diff, 0040's `plan.md`, Deviations; the handover's "Left open")
- Spec needed: yes
- Status: planned
- Opened: 2026-10-30
- Decided: 2026-10-30
- Supersedes: —
- Mode: bootstrap

## Problem

A realm export may hold a brute-force setting in its `attributes`, which Keycloak writes after the export's fields when it creates the realm (0041). When an attribute holds one of the ten settings as `null`, `register-app.sh` counts the setting as not held and sends the stack's value, which Keycloak then overwrites with the null attribute (26.8.1, `DefaultExportImportManager.importRealm:413-416`, `RealmAdapter.updateAttribute`): Keycloak's own default applies (`bruteForceProtected` off, no temporary lockout for `maxFailureWaitSeconds`, 0 for `failureFactor`), while the registration says the stack's value was given, and doesn't say the detection is off. Whether Keycloak's database even takes a null attribute isn't known: with `--reset-realms`, the realm would be deleted before the import fails. No real export holds one today.

## Proposed outcome

An export whose `attributes` hold one of the ten brute-force settings as `null` is refused, in dev as on the demo host, before anything changes, naming the file and the setting.

Success criterion: such an export registers nothing and says why; an export without one registers as before.

## Affected users and systems

- Application (any whose export is edited by hand), Developer, Demo visitor (the demo accounts' lockout).
- Registration (`register-app.sh`), README ("Brute-force protection"), `docs/migration.md`.

## Constraints

- 0041: each setting the export holds is kept as it says; a setting given as `null` at the export's top level counts as not held, the stack's value filling it (Jackson leaves the field unset).

## Decided at acceptance (the product owner, 2026-10-30)

- Refused everywhere ("Ok pour ta recommandation"). Set aside: the null counted as the export's choice, Keycloak's default then applying, the registration saying so.
