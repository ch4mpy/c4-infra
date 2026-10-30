# Intent: The stand-in demo host can't serve an application over HTTPS

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: change
- Source: conversation (2026-10-28, the skills' intent 0099, its spec's PA-07: the stand-in's HTTPS asked of c4-infra first)
- Spec needed: yes
- Status: delivered (2026-10-30)
- Opened: 2026-10-28
- Decided: 2026-10-28
- Supersedes: —
- Mode: bootstrap

## Problem

The stand-in demo host (`tests/lib/stand-in-host.sh`) runs the demo stack in a privileged container, with Caddy started without ACME (`tests/stand-in-host/compose.no-acme.yml`): it has no certificate to serve. The stand-in tests check an application's site only up to Caddy's redirect from HTTP to HTTPS (`tests/0003-demo-deploy.stand-in.sh:104-105`).

The skills now need more: their intents 0095 (a generated front end on the demo host) and 0099 (the whole generated project on it) prove their success criterion on the stand-in, and 0099's has a user log in through the shared proxy, which only works over HTTPS (the session cookie, Keycloak's `sslRequired`). Both specs chose to ask c4-infra for this first (the skills' 0099, PA-07 B) rather than work around Caddy in their own tests.

## Proposed outcome

A test can ask the stand-in demo host to serve each registered site over HTTPS, with certificates from a local authority the test trusts in its own client, without changing what the real demo host does.

Success criterion: a stand-in test registers an application, requests one of its pages over HTTPS through the stand-in's Caddy and gets it, its client trusting only the stand-in's local authority; the existing stand-in tests pass unchanged.

## Affected users and systems

- Developer (c4-infra's tests, the skills' tests that use the stand-in).
- `tests/lib/stand-in-host.sh`, `tests/stand-in-host/`, the demo's Caddy configuration (read, not changed for the real host).

## Constraints

- The real demo host keeps its ACME certificates and its configuration unchanged.
- The local authority's key stays in the test's temporary files and is never committed nor written to the real host.
- It works on both workstations (Docker Desktop on Windows, Docker on Ubuntu).

## Open questions

- How the stand-in gets its certificates (Caddy's internal authority, a test authority the stand-in is given) — spec.
- Whether it is an option of the stand-in or always on — the PO, at the spec.
