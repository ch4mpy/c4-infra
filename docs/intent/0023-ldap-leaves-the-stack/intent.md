# Intent: The stack still documents and tests an LDAP user federation no application needs

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: change
- Source: conversation (2026-10-28, planning 0021)
- Spec needed: yes
- Status: planned
- Opened: 2026-10-28
- Decided: 2026-10-28
- Supersedes: —
- Mode: bootstrap

## Problem

The shared stack carries an LDAP server that Keycloak federates, a Keycloak demonstration element from Tickee's realm `tenant2`:

- `README.md` gives "Tickee's LDAP server" as the example of an application's container the shared services must reach;
- `docs/migration.md` moves Tickee's `tenant2` onto the stack with its federation of `ldap://tickee.ldap-tenant2:389` and its `ldap2` container on Tickee's network;
- `tests/0007-dev.sh` proves the dev isolation (0007's AC-07, after its RQ-08) with an `osixia/openldap:1.5.0` stand-in that Keycloak federates; its control check fails now and then (intent 0021, abandoned for this one).

In the general case Keycloak's own user database is enough. An LDAP server costs a container to run and to monitor, and a user federation to configure in each realm that uses it: the stack is simpler without it.

## Proposed outcome

Nothing of the stack (its docs, tests and examples) relies on or describes an LDAP user federation: an application's users live in Keycloak's database. The migration guide moves `tenant2`'s users into Keycloak's database, without an LDAP container. The dev isolation stays proven, with a check that needs no LDAP in place of 0007's AC-07.

## Affected users and systems

- Personas: Developer (follows the migration guide, runs the verification); Application (Tickee, its realm `tenant2`)
- Modules / systems: the docs (`README.md`, `docs/migration.md`), the dev isolation test (`tests/0007-dev.sh`)

## Constraints

- 0007's other criteria hold: an application's containers on its own network in dev too (its RQ-08), with another example than an LDAP server.
- 0007 stays delivered: this intent's spec names what of it is replaced.

## Open questions

- Whether a registration refuses a realm that federates an LDAP server, or any user federation, which would keep it out for good — the spec (product owner).
- What replaces AC-07's check: a container of Tickee's network that Keycloak reaches and another application's network doesn't (e.g. an HTTP stand-in, as a gateway's back-channel logout endpoint) — the spec.
