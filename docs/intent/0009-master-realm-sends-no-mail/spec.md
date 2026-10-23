# Spec: Keycloak's master realm sends no mail

- Intent: [0009](intent.md)
- Status: draft
- Version: 1
- Risk: high (rules: authentication, authorization and secrets — Mailpit's SMTP password written into Keycloak, an administrator's credentials, the reset of the master realm's administrators' passwords by mail (PA-3), and possibly a new right of the registration account (PA-1); tech lead's agreement required)
- Policies applied: none yet; standing constraints: README design, `CLAUDE.md` (no password on a command line), 0006 (the registration account's rights)
- Approved: —

## Summary

Each start of the shared stack (`up.sh` in dev, a deployment on the demo host) gives Keycloak's master realm Mailpit's SMTP settings when it has none, as an administrator, and leaves them alone otherwise; with them, it turns on the master realm's *Forgot password* and *Verify email*. The current demo host and the existing dev stacks get them at their next start. A documented step writes them again after a change of Mailpit's SMTP password.

## Requirements

- REQ-1 After a start of the stack, a master realm that had no SMTP server has Mailpit's, with its SMTP credentials: in dev `host.docker.internal:1025` with STARTTLS (Mailpit requires it there, and only that name is in the local leaf), on the demo host `mailpit:1025` without TLS (as `compose.demo.yml` allows inside the Docker networks); sender `noreply@<INFRA_HOST>`. (intent: outcome; constraint: each environment's Mailpit)
- REQ-2 A master realm that already has an SMTP server keeps it as it is, whatever its values. (intent: outcome, written once)
- REQ-3 The stack knows whether the master realm has an SMTP server without an administrator's login (PA-1); an administrator logs in only to write the settings: the bootstrap administrator of `.env` while it works, else `KC_SETUP_ADMIN_*` (demo host) or the one a terminal gives (dev), as for the registration account (0006, REQ-3). (intent: criterion, after the bootstrap administrator is replaced)
- REQ-4 When the settings must be written and no administrator logs in, the start → PA-2, with a message that names the setting and how to give an administrator. (intent: outcome)
- REQ-5 One documented step writes the settings again after a change of `MAILPIT_SMTP_PASSWORD`: emptying the *Host* of the master realm's *Email* settings in the console, then a start (`up.sh`, a deployment), with an administrator as in REQ-3. (intent: outcome, decided on acceptance)
- REQ-6 Mailpit's SMTP password appears on no command line, in no output of the start, and in nothing the repository holds. (intent: constraint)
- REQ-7 The registration account still may not change the master realm (0006, REQ-2 and AC-2). (intent: constraint)
- REQ-8 When the stack writes the master realm's SMTP settings (REQ-1), it also turns on its *Forgot password* (`resetPasswordAllowed`): the master realm's login page offers to reset a password by mail. Turned off afterwards in the console, it stays off. (product owner's request after acceptance; intent: problem, "a forgotten password"; PA-3)
- REQ-9 At the same time, it turns on the master realm's *Verify email* (`verifyEmail`): an account of the master realm whose e-mail address isn't verified is asked to verify it, by mail, at its next login. Turned off afterwards in the console, it stays off. (product owner's request after acceptance; PA-4)

## Out of scope

- The applications' realms: each still renders its own SMTP settings (`docs/migration.md`).
- Mailpit's own configuration, and the master realm's other settings (brute force: 0010).
- *Forgot password* and *Verify email* in the applications' realms: each application's realm export decides.

## Design

### Current behaviour

- Nothing writes the master realm's SMTP settings: `compose.yml:143` gives Mailpit its credentials for "the realms' smtpServer", which each application renders into its own realm. Dev at `08dfa3d`: `get realms/master --fields smtpServer` answers `"smtpServer" : { }`; the demo host, deployed at the same commit, shows an empty *Email* tab.
- Mailpit in dev has SMTP credentials and a certificate but no `MP_SMTP_AUTH_ALLOW_INSECURE`, so it requires STARTTLS (Mailpit's `VerifyConfig`); the leaf's names are `host.docker.internal`, `localhost`, `*.dev.localhost`, `127.0.0.1` (`openssl x509 -ext subjectAltName`), and Keycloak trusts the local CA (`KC_TRUSTSTORE_PATHS`, `compose.dev.yml`). The applications' realms already use `host.docker.internal:1025` in dev (`README.md:167`).
- The registration account sees a reduced view of the master realm, without its SMTP settings: `bruteForceProtected`, `displayName`, `displayNameHtml`, `organizationsEnabled`, `realm`, `supportedLocales` (dev, `kc_registration get realms/master`). Only an administrator, or an account with the master realm's `view-realm`, reads `smtpServer`, its password masked by Keycloak.
- `registration-account.sh ensure`, run by `up.sh` and `demo/deploy.sh` after each start, already logs in as an administrator only when something must be repaired (0006).
- Dev: the master realm answers `resetPasswordAllowed: false`, `verifyEmail: false` (Keycloak's defaults), and its only account, `admin`, has no e-mail address (`emailVerified: false`). The stack and the tests log in as that administrator with the admin CLI (password grant), which Keycloak refuses to an account with a pending required action ("Account is not fully set up"), such as *Verify email* for an address not verified.
- On the demo host, Mailpit's UI and API (user `demo`) show every mail the stack's Keycloak sends, whatever its realm (`compose.demo.yml`, 0007).

### Behaviour per persona

- Demo operator: after the next deployment, the master realm's *Test connection* delivers to Mailpit (`/mailpit/`); after a change of `MAILPIT_SMTP_PASSWORD`, follows the documented step (`docs/demo-setup.md`).
- Developer: the same after `bash up.sh`, the mails in `https://host.docker.internal/mailpit/`.
- An administrator of the master realm (operator, developer): the login page of `/auth/admin/` offers *Forgot password?*, whose mail lands in Mailpit (only for an account with an e-mail address); an administrator who sets an e-mail address verifies it at the next login, from the mail in Mailpit, before the admin CLI logs in as them again.

### API and contracts

- Master realm's `smtpServer` (Keycloak's admin API): `host`, `port` `1025`, `from` `noreply@<INFRA_HOST>`, `fromDisplayName` `Keycloak`, `auth` `true`, `user` `MAILPIT_SMTP_USER`, `password` `MAILPIT_SMTP_PASSWORD`, `starttls` `true` in dev / `false` on the demo host, `ssl` `false`.
- Master realm: `resetPasswordAllowed` `true`, `verifyEmail` `true`, written with the SMTP settings (REQ-8, REQ-9).
- No new setting nor secret: `.env` already holds `MAILPIT_SMTP_USER` and `MAILPIT_SMTP_PASSWORD`, in dev (`env.sh`) as on the demo host (`demo/write-env.sh`).
- Messages of the start: settings written, already present, or missing with no administrator (REQ-4).

### User interface

None (the console's *Email* tab shows the settings).

### Data

The master realm's SMTP settings, in Keycloak's database; with PA-1 B, one more role of the registration account.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| No password on a command line (`CLAUDE.md`) | REQ-6 |
| 0006 REQ-2: the registration account, nothing else in the master realm | REQ-7 for writes; reads → PA-1 |
| README design | unchanged |

## Points of attention

### PA-1 How the stack knows the master realm has no SMTP settings

- Issue: the registration account doesn't see them (reduced view); an administrator's login at every start would, once the bootstrap administrator's password is changed in the console, fail at every `up.sh` and every deployment, and with 0010's lockout lock that administrator out.
- Options: A an administrator logs in at every start to read them / B the registration account also gets the master realm's `view-realm` (read only: the master realm's settings, passwords masked by Keycloak; no write, no users, no clients), and an administrator logs in only to write them / C they are written only when the registration account is created or repaired (an administrator is logged in then), and the current demo host and dev stacks need a one-off manual step
- Recommendation: B: no administrator's login while nothing is to be written, no manual step for the existing stacks; it relaxes 0006's REQ-2 for reads only, and a leaked secret then reveals the master realm's settings, not its credentials.
- Decides: tech lead
- Decision: to decide

### PA-2 Settings to write and no administrator who logs in

- Issue: on the demo host, without `KC_SETUP_ADMIN_*` once the bootstrap administrator is gone; in dev, without a terminal.
- Options: A the start fails, as the registration account's repair does (0006) / B the start goes on, and says the master realm sends no mail and how to give an administrator (a workflow warning on the demo host)
- Recommendation: B: the master realm's mails don't justify stopping a deployment the applications rely on, and the case only arises on a stack whose bootstrap administrator was replaced before its first start with this change.
- Decides: product owner
- Decision: to decide

### PA-3 *Forgot password* makes Mailpit's readers able to reset an administrator's password

- Issue: on the demo host, a reset mail for an administrator of the master realm lands in Mailpit, where whoever holds Mailpit's UI credentials (user `demo`) reads it, and can then take over Keycloak, every application's realm included. It only works for an administrator with an e-mail address (none by default).
- Options: A *Forgot password* on in dev and on the demo host, and Mailpit's UI credentials are the operators' only: `docs/demo-setup.md` says never to give them to the demo's visitors / B on in dev only; off on the demo host (no reset of an administrator's password there but by another administrator) / C on everywhere, the risk accepted as it is
- Recommendation: A if no visitor is ever to read Mailpit; B otherwise, since the applications' visitors may need Mailpit to read their own mails (verification, reset) in their realms.
- Decides: product owner, with the tech lead's agreement (high risk)
- Decision: to decide

### PA-4 *Verify email* and the stack's administrator logins

- Issue: an administrator whose e-mail address isn't verified has a pending action: Keycloak refuses their admin CLI login, which the stack uses to repair the registration account and write these settings (0006, REQ-3) and the tests use. The bootstrap administrator has no address, so nothing changes until one is set.
- Options: A accepted: an administrator who sets an address verifies it at once (mail in Mailpit), as `docs/demo-setup.md` and the README say; the stack's message names the cause when that login is refused / B *Verify email* off in the master realm
- Recommendation: A: the action only appears when an address is set, and its mail arrives at once in Mailpit.
- Decides: product owner
- Decision: to decide

## Acceptance criteria

- AC-1 Given a dev stack without its volumes, when `bash up.sh` runs, then the master realm's SMTP settings are REQ-1's for dev, and its *Test connection* (the admin API's `testSMTPConnection`, as an administrator with an e-mail address) delivers a mail that shows in Mailpit. (REQ-1)
- AC-2 Given the stand-in demo host, when the deployment runs, then the same holds with the demo host's settings. (REQ-1)
- AC-3 Given a master realm with other SMTP settings, when the stack starts, then they are unchanged and, with PA-1 B, no administrator logs in. (REQ-2, REQ-3)
- AC-4 Given this workstation's stack and the current demo host (settings missing, registration account created before this change), when they start once, then their master realm gets the settings. (REQ-1, REQ-3)
- AC-5 Given the bootstrap administrator replaced and deleted, settings present, when the stack starts, then it succeeds and the master realm still delivers. (REQ-3)
- AC-6 Given settings missing and no administrator, when the deployment runs, then it behaves as PA-2 decides, with REQ-4's message. (REQ-4)
- AC-7 Given `MAILPIT_SMTP_PASSWORD` changed and the documented step followed, then the master realm's *Test connection* delivers again. (REQ-5)
- AC-8 While the settings are written, Mailpit's SMTP password is neither in the host's process list nor in the start's output. (REQ-6)
- AC-9 Given the registration account, when it tries to change the master realm, then Keycloak still refuses. (REQ-7)
- AC-10 Given a start that writes the SMTP settings, then the master realm's *Forgot password* and *Verify email* are on (as PA-3 decides on the demo host); given them turned off in the console, a later start leaves them off. (REQ-8, REQ-9)
- AC-11 Given an administrator with a verified e-mail address, when *Forgot password?* is asked for on `/auth/admin/`, then the reset mail shows in Mailpit and its link sets a new password. (REQ-8)
- AC-12 Given an administrator whose e-mail address isn't verified, when they log in to the console, then Keycloak asks them to verify it and the mail shows in Mailpit; their admin CLI login is refused until then, and the stack's message says why. (REQ-9, PA-4)

## Intent questions

- *Suggested solution*: the stack sets the master realm's SMTP server itself, as an administrator, when it starts, next to the registration account's check → REQ-1, REQ-3, PA-1.

## Change log

- v1 — 2026-10-23 — first version; REQ-8 and REQ-9 (*Forgot password*, *Verify email*) added at the product owner's request after the intent's acceptance: beyond the intent's text, flagged, with PA-3 and PA-4
