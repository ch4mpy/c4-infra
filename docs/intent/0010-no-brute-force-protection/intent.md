# Intent: No realm of the shared Keycloak protects its accounts against password guessing

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: change
- Source: conversation (first deployment of the demo host, 2026-10-23)
- Spec needed: yes
- Status: delivered
- Opened: 2026-10-23
- Decided: 2026-10-23
- Delivered: 2026-10-23 (PR #2)
- Supersedes: —

## Problem

Keycloak creates every realm with its brute-force detection off, and c4-infra turns it on nowhere: anyone can try passwords without limit against any account of the shared Keycloak.

- The master realm's administrators: their console is public on the demo host (`https://infra.c4-soft.com/auth/admin/`).
- The accounts of every application's realm: each application decides in its own realm export, or not at all.

Observed in dev at `08dfa3d`: realms `master` and `faito` answer `bruteForceProtected: false` (Keycloak's default for a new realm).

## Proposed outcome

Every realm of the shared Keycloak — the master realm and every application's realm, those registered later included — locks an account temporarily after repeated failed logins, the wait growing with each further failure, never for good; in dev and on the demo host.

Success criterion: after 10 failed logins of an account, a login with its right password is refused for 1 minute; each further failure adds 1 minute, up to 15 minutes; failures are forgotten 12 hours after the last one; once the wait is over, the right password logs in; nothing locks an account permanently.

The settings are c4-infra's, for every realm: an application's realm gets them when it is registered, the master realm when the stack starts; c4-infra doesn't watch them afterwards (decided in the interview).

## Affected users and systems

- Demo operator, Developer, Application, Demo visitor (an account can be locked for a while).
- Registration (`register-app.sh`), dev stack and demo stack (Keycloak's master realm).

## Constraints

- Never a permanent lockout.
- The registration account keeps no right to change the master realm (0006, REQ-2).
- No password on a command line.

## Open questions

- On the demo host, a visitor can lock a shared demo account (public password) for up to 15 minutes: accepted? — product owner
- The realms already registered before this change (Faito's in dev): do they get the protection? — product owner
- *Suggested solution*: the registration sets the protection on each realm it registers, and the stack sets the master realm's when it starts, as 0009 does for its SMTP settings — to be settled in the spec. — tech lead
