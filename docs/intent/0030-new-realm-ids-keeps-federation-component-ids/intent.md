# Intent: new-realm-ids.sh leaves a user federation component's id as it was

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: bug
- Source: conversation (the alignment analyses of Tickee and poc-immo-pf on c4-infra, 2026-10-28)
- Spec needed: no
- Status: accepted
- Opened: 2026-10-28
- Decided: 2026-10-28
- Supersedes: —
- Mode: bootstrap

## Problem

`new-realm-ids.sh` gives a realm export new ids, so that two realms cloned from one export can both be imported ("Duplicate resource error"). It replaces the UUIDs (`new-realm-ids.sh`, its `uuid` pattern); a user federation component's id isn't one (Tickee's tenant2 LDAP: `yF3TX8w9ReakazORRBtTAQ`, cited by its users' `federationLink`), and stays as it was.

- Steps: a realm export holding an LDAP user federation, cloned into a second realm file, both run through `new-realm-ids.sh`, both imported.
- Expected: both imported, each with its own component.
- Observed: read in the script, not reproduced: the component's id, and its users' `federationLink`, the same in both files.
- Environment: c4-infra `main`, 2026-10-28.

## Proposed outcome

`new-realm-ids.sh` gives a realm export new ids for every id an import must find unique, a user federation component's included, its users' links following.

## Affected users and systems

- Personas: Application (one that federates a directory: Tickee)
- Modules / systems: registration (`new-realm-ids.sh`)

## Constraints

- An export the script already rewrote still imports.

## Open questions

- Whether Keycloak 26.8.1 refuses the second import, or which ids it needs unique — the plan measures it.
