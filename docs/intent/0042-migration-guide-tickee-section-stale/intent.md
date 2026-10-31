# Intent: The migration guide describes Tickee as it was before its migration

- Author: Jérôme Wacongne (product owner, tech lead); drafted by the agent from the reading of Tickee of 2026-10-30
- Kind: change
- Source: conversation (2026-10-30: Tickee's intent 0001, delivered 2026-10-29, and its deviations)
- Spec needed: no
- Status: delivered (2026-10-30)
- Opened: 2026-10-30
- Decided: 2026-10-30
- Supersedes: —
- Mode: bootstrap

## Problem

`docs/migration.md`'s Tickee section (`:342-348`) still says that `tenant2` federates `ldap://tickee.ldap-tenant2:389` and that the realm `tickee` has two BFF clients with back-channel logout, `gateway` and `tickee-bff`. Tickee, migrated on 2026-10-29, runs 389 Directory Server on `3389`, federated without a periodic sync, and dropped the `gateway` client. And the guide's port table (`:46-55`) has no row for a service of the application's own that a developer reaches from the workstation: Tickee published its directory on `127.0.0.1:13389` without a rule to follow.

## Proposed outcome

The guide's Tickee section says what Tickee runs today, and the port table says which port of its block an application gives a service of its own.

Success criterion: the section names 389 Directory Server on `3389`, no periodic sync, one BFF client `tickee-bff`; the table has a row for such a service, Tickee's directory as the example.

## Affected users and systems

- Developer (an application's migration), `docs/migration.md`.

## Constraints

- The guide keeps describing what the stack provides, not Tickee's own choices beyond what another application needs to know.
