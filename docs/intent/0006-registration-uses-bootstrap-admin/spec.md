# Spec: Registrations depend on Keycloak's temporary bootstrap administrator

- Intent: [0006](intent.md)
- Status: draft
- Version: 1
- Risk: high (rules: authentication, authorization and secrets — the credential that creates and deletes every application's realm; tech lead's agreement required)
- Policies applied: none yet; standing constraints: README design, `CLAUDE.md` (no password on a command line)
- Approved: —

## Summary

Registrations authenticate with a dedicated service account of Keycloak's master realm, created once and holding only what registering takes, instead of the temporary bootstrap administrator. Its secret lives in `.env` (dev) and in a secret of the `demo` environment, and can be rotated.

## Requirements

- REQ-1 `register-app.sh` authenticates to Keycloak with a dedicated service account, by client credentials, never with a user's password. (intent: proposed outcome)
- REQ-2 The account can create a realm, and manage and delete the realms it created; nothing else in the master realm (PA-1 decided). (intent; risk rules: least privilege)
- REQ-3 The account is created once, on the first start of the stack, with the bootstrap administrator; later starts leave it alone (PA-2 decided). (intent: proposed outcome)
- REQ-4 Replacing the bootstrap administrator by a permanent one and deleting it, or changing its password, doesn't affect registrations. (intent: success criterion)
- REQ-5 Rotating the account's secret takes one documented step, after which the next registration works. (intent: success criterion)
- REQ-6 The secret stays off command lines and out of the repository (`.env` in dev, a secret of the `demo` environment on the demo host). (intent: constraint)

## Out of scope

- The applications' own Keycloak clients and service accounts.
- Keycloak's administrators for humans (console access).

## Design

### Current behaviour

`register-app.sh`: `kcadm.sh … --realm master --user "$KC_BOOTSTRAP_ADMIN_USERNAME"` with `KC_CLI_PASSWORD` from `KC_BOOTSTRAP_ADMIN_PASSWORD` (`.env`, the `KC_ADMIN_PASSWORD` secret on the demo host); Keycloak reads these on its first start only and flags the account as temporary. The README warns not to replace it.

### Behaviour per persona

- Demo operator and developer: may replace Keycloak's temporary administrator as the console suggests.
- Application: registers as before.

### API and contracts

- `.env` / `demo` environment: the service account's client id and secret (names settled in the plan); `docs/demo-setup.md` lists the new secret.
- `register-app.sh`: same options, another credential.

### User interface

None.

### Data

A client in Keycloak's master realm, with its roles.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| No password on a command line | REQ-6: the secret through the environment, as today |
| README design | unchanged |

## Points of attention

### PA-1 The account's rights

- Issue: deleting a realm (`--reset-realms`) and importing one take more than creating it.
- Options: A the master realm's `admin` role (simple, everything) / B `create-realm`, plus the management of each realm it created (Keycloak grants the creator the realm's administration)
- Recommendation: B: a leaked secret can't touch the master realm nor a realm it didn't create.
- Decides: tech lead
- Decision: to decide

### PA-2 Who creates the account

- Options: A `up.sh` (dev) and the deployment workflow (demo host), with the bootstrap administrator, on the stack's first start / B Keycloak's bootstrap service account (`KC_BOOTSTRAP_ADMIN_CLIENT_ID`), itself flagged temporary
- Recommendation: A: a permanent account, created once, independent of the temporary ones.
- Decides: tech lead
- Decision: to decide

## Acceptance criteria

- AC-1 Given the stack started, when the temporary administrator is replaced by a permanent one and deleted, then Faito's registration with `--reset-realms` still imports its realm. (REQ-1, REQ-4)
- AC-2 Given the account, when it tries to change the master realm or a realm it didn't create, then Keycloak refuses. (REQ-2)
- AC-3 Given a second `up.sh`, then the account is unchanged. (REQ-3)
- AC-4 Given the secret rotated as documented, then the next registration works, and one with the former secret fails. (REQ-5)
- AC-5 While a registration runs, the secret appears neither in the host's process list nor in `docker inspect`. (REQ-6)

## Intent questions

- A dedicated service account in the master realm → PA-1, PA-2.

## Change log

- v1 — 2026-10-21 — first version
