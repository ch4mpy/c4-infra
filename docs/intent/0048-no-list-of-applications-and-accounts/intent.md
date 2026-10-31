# Intent: Nothing tells a visitor which applications are deployed, nor which account to sign in with

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: change
- Source: conversation (2026-10-30, the product owner's request after the triage of the handover)
- Spec needed: yes
- Status: specified
- Opened: 2026-10-30
- Decided: 2026-10-30
- Supersedes: —
- Mode: bootstrap

## Problem

The demo host shows use cases: the product owner, or someone they send there, opens an application and signs in. Nothing on the host says which applications it runs, nor with which accounts: the root of `https://infra.c4-soft.com/` answers `404` "c4-infra: the applications are on their own host names" (`caddy/Caddyfile`, a test asserts it: `tests/0003-demo-edge.sh:129`), and each application's accounts are known only from its own repository. In dev, `register-app.sh` writes a landing page that links the shared services and each registered application (`register-app.sh:112-134`, `https://host.docker.internal/`), without any account.

The stack can't find these accounts by itself: the realm exports hold password hashes (Faito's two users, Tickee's `brasserie` and `tenant3` realms) or no password at all (Tickee's `tenant2` realm reads its users from its LDAP directory, read-only; its `tickee` realm brokers the others).

## Proposed outcome

A page lists each application the environment runs, its link and the accounts to sign in with, in dev and on the demo host, kept up to date by the registrations. It needs no translation: an application's name and a list of accounts.

Success criterion: once an application is registered with its accounts, the page shows its link and those accounts, in dev and on the demo host; an application registered without accounts shows its link only.

## Affected users and systems

- Demo visitor, Developer, Application (declares its accounts), Demo operator.
- Reverse proxy (`caddy/`), registration (`register-app.sh`), demo host (`demo/c4-app`, `demo/deploy.sh`).

## Constraints

- On the demo host, the page is served on the infra host, the origin of Keycloak and of its administration console (`https://infra.c4-soft.com/auth/`): nothing an application declares may run there.
- Only accounts that exist for the demo, whose password is used nowhere else, are ever listed (the product owner's acceptance below).
- The demo host can be reset at any time (README, "Demo host").

## Decided at acceptance (the product owner, 2026-10-30)

- The applications' accounts are published, in dev and on the demo host ("J'accepte de publier les comptes des applications en dev et en démo").
- The page is generated and shown in dev too.
- No translation: the application's name and a list of accounts.

## Open questions

- *Suggested alternative, to study*, from the product owner: a random password generated at each deployment and shown by the application's CI (a comment, the run's summary), rather than on a public page. → the spec.
