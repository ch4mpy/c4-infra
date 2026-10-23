# Intent: Keycloak's master realm sends no mail

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: bug
- Source: conversation (first deployment of the demo host, 2026-10-23)
- Spec needed: yes
- Status: proposed
- Opened: 2026-10-23
- Decided: —
- Supersedes: —

## Problem

The master realm of the shared Keycloak has no SMTP server, on the demo host as in dev: nothing in c4-infra sets one. Mailpit's SMTP settings only reach the applications' realms, which each application renders itself.

- Keycloak sends no mail for the master realm's accounts: the console's *Test connection*, the e-mail actions on an administrator's account (verify e-mail, update password), a forgotten password when it is enabled. They fail, and nothing shows in Mailpit.
- The operator fills the settings in by hand, in the console, with Mailpit's SMTP password: on each new host, and again in dev whenever the stack's volumes are removed.

Steps to reproduce: deploy the demo host, or `bash up.sh` in dev; open `/auth/admin/`, realm master, *Realm settings* → *Email*.

- Expected: Mailpit's SMTP server and credentials, as in the applications' realms.
- Observed: no host. Demo host `infra.c4-soft.com`, commit `08dfa3d`, deployed on 2026-10-23; dev stack at the same commit, where `get realms/master --fields smtpServer` answers `{ }`.

## Proposed outcome

The master realm's mails reach Mailpit with no manual step, in dev and on the demo host, the host already deployed included. Success criterion: after `bash up.sh` or a deployment, on a fresh stack as on the current demo host, the console's *Test connection* of the master realm delivers a mail that shows in Mailpit, and it still does once the bootstrap administrator has been replaced (0006).

## Affected users and systems

- Demo operator, Developer.
- Dev stack and demo stack (Keycloak's master realm, Mailpit); possibly the deployment workflow (secrets).

## Constraints

- The registration account keeps no right on the master realm (0006, REQ-2).
- Mailpit's SMTP password stays off command lines and out of the repository.
- The applications' realms are unchanged: each still renders its own SMTP settings.
- Each environment's Mailpit is reached as it is today: STARTTLS with the local CA in dev (`compose.dev.yml`), plain SMTP inside the Docker networks on the demo host (`compose.demo.yml`).

## Open questions

- When Mailpit's SMTP password changes (`MAILPIT_SMTP_PASSWORD`), does the master realm follow it, or are its settings written once? — product owner
- *Suggested solution*: the stack sets the master realm's SMTP server itself, as an administrator, when it starts (`up.sh`, `demo/deploy.sh`), next to the registration account's check — to be settled in the spec. — tech lead
