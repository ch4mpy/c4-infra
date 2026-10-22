# Spec: Registrations depend on Keycloak's temporary bootstrap administrator

- Intent: [0006](intent.md)
- Status: draft
- Version: 1
- Risk: high (rules: authentication, authorization and secrets — the credential that creates and deletes every application's realm; tech lead's agreement required)
- Policies applied: none yet; standing constraints: README design, `CLAUDE.md` (no password on a command line)
- Approved: —

## Summary

Registrations authenticate with a dedicated service account of Keycloak's master realm, held by the shared stack only (on the demo host, applications register through it: 0002). It can create realms and manage the realms the registry assigns to the applications, existing ones included, and nothing else. It is created whenever it is missing, and its secret can be rotated.

## Requirements

- REQ-1 `register-app.sh` authenticates to Keycloak with a dedicated service account, by client credentials, never with a user's password. (intent: proposed outcome)
- REQ-2 The account can create a realm and manage, import into and delete the realms the registry assigns to the applications (0004), realms created before the account included; nothing else in the master realm (PA-1 decided). (intent; risk rules: least privilege)
- REQ-3 The account is created whenever the stack starts without it, by `up.sh` in dev and by the deployment workflow on the demo host, with the bootstrap administrator's credentials or, once those are gone, an administrator's credentials the operator gives once (PA-2 decided). (intent: proposed outcome; existing stacks)
- REQ-4 A registration tells a realm that doesn't exist from one the account may not see, and reports the second instead of trying to create it. (existing stacks)
- REQ-5 Replacing the bootstrap administrator by a permanent one and deleting it, or changing its password, doesn't affect registrations. (intent: success criterion)
- REQ-6 Rotating the account's secret takes one documented step, after which the next registration works. (intent: success criterion)
- REQ-7 The secret never appears on a command line, in a container's configuration, nor in the repository: `.env` in dev, a secret of the `demo` environment on the demo host, readable by the shared stack's account only (0002). (intent: constraint)

## Out of scope

- The applications' own Keycloak clients and service accounts.
- Keycloak's administrators for humans (console access).

## Design

### Current behaviour

`register-app.sh`: `kcadm.sh … --realm master --user "$KC_BOOTSTRAP_ADMIN_USERNAME"` with `KC_CLI_PASSWORD` from `KC_BOOTSTRAP_ADMIN_PASSWORD` (`.env`, the `KC_ADMIN_PASSWORD` secret on the demo host); Keycloak reads these on its first start only and flags the account as temporary. The README warns not to replace it. The admin CLI takes a client secret as an argument (`--secret`), which REQ-7 forbids: the plan has to pass it another way (its environment, its standard input, or a token obtained over HTTP with the secret in the request body).

### Behaviour per persona

- Demo operator and developer: may replace Keycloak's temporary administrator as the console suggests.
- Application: registers as before (through 0002's command on the demo host).

### API and contracts

- `.env` / `demo` environment: the service account's client id and secret (names settled in the plan); `docs/demo-setup.md` lists the new secret.
- `register-app.sh`: same options, another credential, a new message for a realm it may not see (REQ-4).

### User interface

None.

### Data

A client in Keycloak's master realm, with its roles.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| No password on a command line | REQ-7 |
| README design | unchanged |

## Points of attention

### PA-1 The account's rights (decided)

- Issue: deleting a realm (`--reset-realms`) and importing one take more than creating it; existing realms were created by the bootstrap administrator.
- Options: A the master realm's `admin` role (simple, everything) / B `create-realm`, plus the management of each realm the registry assigns, granted when the account is created and when a realm is added
- Recommendation: B: a leaked secret can't touch the master realm nor a realm no application owns.
- Decides: tech lead
- Decision: B, `create-realm` and the registered realms' management (tech lead, 2026-10-21)

### PA-2 Who creates the account (decided)

- Issue: the account must exist on existing stacks too, whose bootstrap administrator may already be gone.
- Options: A `up.sh` (dev) and the deployment workflow (demo host), whenever it is missing / B Keycloak's bootstrap service account (`KC_BOOTSTRAP_ADMIN_CLIENT_ID`), itself flagged temporary and created on the first start only
- Recommendation: A: a permanent account, created where and when it is missing.
- Decides: tech lead
- Decision: A, created whenever it is missing (tech lead, 2026-10-21)

## Acceptance criteria

- AC-1 Given the stack started, when the temporary administrator is replaced by a permanent one and deleted, then Faito's registration with `--reset-realms` still imports its realm. (REQ-1, REQ-5)
- AC-2 Given the account, when it tries to change the master realm or a realm no registry entry assigns, then Keycloak refuses. (REQ-2)
- AC-3 Given this workstation's stack (started before this change, realm `faito` created by the bootstrap administrator), when `up.sh` runs, then the account is created and Faito's next registration finds its realm. (REQ-2, REQ-3)
- AC-4 Given a realm the account may not see, when a registration targets it, then it reports so and creates nothing. (REQ-4)
- AC-5 Given the secret rotated as documented, then the next registration works, and one with the former secret fails. (REQ-6)
- AC-6 While a registration runs, the secret appears neither in the host's process list nor in `docker inspect`. (REQ-7)

## Intent questions

- A dedicated service account in the master realm → PA-1, PA-2.

## Change log

- v1 — 2026-10-21 — first version
- v1 — 2026-10-21 — draft: coherence review (credential held by the shared stack, existing stacks and realms, the secret off the admin CLI's command line), PA-1 and PA-2 decided
