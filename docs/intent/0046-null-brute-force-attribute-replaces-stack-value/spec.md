# Spec: A brute-force setting an export's attributes hold as null replaces the stack's value, while the registration names the stack's

- Intent: [0046](intent.md)
- Status: approved
- Version: 1
- Risk: high (authentication: the brute-force protection of the applications' realms)
- Policies applied: none yet; standing constraints: 0041 (spec v3), CLAUDE.md
- Approved: 2026-10-30, Jérôme Wacongne (PO, also tech lead; in the session, the choice decided at acceptance)

## Summary

`register-app.sh` refuses, in dev as on the demo host, a realm export whose `attributes` hold one of the ten brute-force settings as `null`, before anything changes. 0041's other rules hold.

## Requirements

- **RQ-01:** `register-app.sh` refuses a realm export whose `attributes` hold one of the ten brute-force settings of 0041's RQ-01 with the value `null`, in dev as on the demo host, with the checks of the realm exports (intents 0013, 0041), before any docker call, naming the file and each such setting. (intent: proposed outcome)
- **RQ-02:** A setting given as `null` at the export's top level still counts as not held (0041's RQ-01), and an attribute other than the ten given as `null` is not this check's. (0041, constraint)
- **RQ-03:** README ("Brute-force protection") and `docs/migration.md` say that such an export is refused. (intent: proposed outcome)

## Out of scope

- Realms already in Keycloak.
- A null attribute outside the ten brute-force settings (`maxSecondaryAuthFailures` given as `null` reads as 0, which 0041's RQ-07 accepts).

## Design

- Message per setting: `--realm <file>: attributes.<setting> null, which Keycloak would write over the stack's value: refused`, then `A realm's export gives each brute-force setting it holds a value, or leaves it out (README.md, "Brute-force protection"); nothing was registered.`, exit 1.
- Developer: an export edited by hand with such a null learns it at the registration, before any change; nothing else changes for an export without one.

## Points of attention

None open (the choice was decided at acceptance: refused everywhere).

## Acceptance criteria

- **AC-01:** Given an export whose `attributes` hold `bruteForceProtected: null`, in dev, when `register-app.sh` registers it, then it is refused, naming the file and the setting, before any docker call; with `failureFactor: null` and `maxFailureWaitSeconds: null` in its `attributes`, both are named; on the demo host, `failureFactor: null` there is refused the same way. (RQ-01)
- **AC-02:** Given an export holding `bruteForceProtected: null` at its top level, or `frontendUrl: null` in its `attributes`, in dev, when `register-app.sh` registers it, then it goes past the export's checks (a docker call). (RQ-02)
- **AC-03:** README and `docs/migration.md` say that an export whose `attributes` hold one of the ten as `null` is refused. (RQ-03)

## Intent questions

None open.

## Change log

- v1, 2026-10-30: drafted and approved in the session.
