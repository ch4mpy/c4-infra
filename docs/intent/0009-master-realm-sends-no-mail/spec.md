# Spec: Keycloak's master realm sends no mail

- Intent: [0009](intent.md)
- Status: approved
- Version: 1
- Risk: high (rules: authentication and secrets — Mailpit's SMTP password and the administrator's password given to Keycloak for its master realm, the reset of passwords by mail (PA-3); tech lead's agreement required)
- Policies applied: none yet; standing constraints: README design, `CLAUDE.md` (no password on a command line), 0006 (the registration account's rights)
- Approved: 2026-10-23, Jérôme Wacongne (PO, and tech lead for the high risk)

## Summary

Keycloak's master realm is created pre-configured: Mailpit's SMTP settings, its administrator with the e-mail address `admin@<INFRA_HOST>`, *Verify email* on, and *Forgot password* on in dev. The configuration applies when Keycloak creates its master realm (a fresh database) and never to a master realm that exists; the current demo host and the existing dev stacks get it by re-creating their Keycloak database, a documented step.

## Requirements

- REQ-1 When Keycloak creates its master realm (first start on an empty database: a new host, dev volumes removed), the realm has Mailpit's SMTP settings and credentials: in dev `host.docker.internal:1025` with STARTTLS (Mailpit requires it there, and only that name is in the local leaf), on the demo host `mailpit:1025` without TLS (as `compose.demo.yml` allows inside the Docker networks); sender `noreply@<INFRA_HOST>`. (intent: outcome; constraint: each environment's Mailpit)
- REQ-2 A master realm that exists is never changed by this configuration: it applies again only when the realm is re-created (PA-1 decided). (intent: outcome, written once)
- REQ-3 No administrator logs in to apply it: Keycloak applies it while it creates the realm, whoever later replaces the bootstrap administrator. (intent: criterion, after the bootstrap administrator is replaced)
- REQ-4 The master realm's administrator (`KC_BOOTSTRAP_ADMIN_USERNAME`, its password `KC_BOOTSTRAP_ADMIN_PASSWORD` as today) is created with the e-mail address `admin@<INFRA_HOST>`, marked verified (PA-2 decided; verified → PA-5). (product owner's decision on PA-2)
- REQ-5 Documented steps: re-creating Keycloak's database to apply the configuration to an existing stack (the current demo host, a dev stack), with what it loses and what the next start re-creates (the registration account; the applications' realms at their next registration); and, after a change of `MAILPIT_SMTP_PASSWORD`, typing the new password in the master realm's *Email* settings. (intent: outcome; PA-1)
- REQ-6 Mailpit's SMTP password and the administrator's password appear on no command line, in no output of the start, and in nothing the repository holds; Keycloak's container receives them in its environment, as Mailpit's container already holds the SMTP one. (intent: constraint)
- REQ-7 The registration account gets no new right, and still may not change the master realm (0006, REQ-2 and AC-2). (intent: constraint)
- REQ-8 *Forgot password* (`resetPasswordAllowed`) is on in the master realm in dev, off on the demo host (PA-3 decided). (product owner's request after acceptance; intent: problem, "a forgotten password")
- REQ-9 *Verify email* (`verifyEmail`) is on in the master realm, in dev and on the demo host: an account of the master realm whose address isn't verified is asked to verify it, by mail, at its next login; `docs/demo-setup.md` and the README say so, and the stack's message names the cause when Keycloak refuses an administrator's login for it (PA-4 decided). (product owner's request after acceptance)

## Out of scope

- The applications' realms: each still renders its own SMTP settings, *Forgot password* and *Verify email* (`docs/migration.md`).
- Changing a master realm that exists, whatever its settings (PA-1).
- Mailpit's own configuration; the master realm's brute-force settings (0010).

## Design

### Current behaviour

- Nothing configures the master realm: Keycloak creates it with its defaults at its first start (`compose.yml`, `command: start`, no realm import); `compose.yml:143` gives Mailpit its credentials for the applications' realms only. Dev at `08dfa3d`: `"smtpServer" : { }`, `resetPasswordAllowed: false`, `verifyEmail: false`, one account `admin` without an e-mail address; the demo host, deployed at the same commit, shows an empty *Email* tab.
- Keycloak 26 (`26.7.4` here) imports the master realm with `--import-realm` when it doesn't exist yet, instead of creating it; a realm that exists is skipped; the import files may take values from the environment (Keycloak's import guide and its 26.0.0 upgrading notes).
- Mailpit in dev has SMTP credentials and a certificate but no `MP_SMTP_AUTH_ALLOW_INSECURE`, so it requires STARTTLS; the leaf's names are `host.docker.internal`, `localhost`, `*.dev.localhost`, `127.0.0.1`, and Keycloak trusts the local CA (`KC_TRUSTSTORE_PATHS`). The applications' realms already use `host.docker.internal:1025` in dev (`README.md:167`).
- The stack and the tests log in as the administrator with the admin CLI (password grant), which Keycloak refuses to an account with a pending required action ("Account is not fully set up"), such as *Verify email* for an address not verified.
- On the demo host, Mailpit's UI and API (user `demo`) show every mail Keycloak sends, whatever the realm (`compose.demo.yml`, 0007).

### Behaviour per persona

- Demo operator: on a new host, the master realm's *Test connection* delivers to Mailpit (`/mailpit/`) from the first deployment; on the current demo host, after the documented re-creation; no *Forgot password?* on `/auth/admin/`.
- Developer: the same after `bash up.sh` on a stack without its volumes; *Forgot password?* on the master realm's login page, its mail in `https://host.docker.internal/mailpit/`.
- An administrator who sets an address that isn't verified verifies it at the next login, from the mail in Mailpit, before the admin CLI logs in as them again.

### API and contracts

- The master realm's configuration, applied by Keycloak when it creates the realm: `smtpServer` (`host`, `port` `1025`, `from` `noreply@<INFRA_HOST>`, `fromDisplayName` `Keycloak`, `auth` `true`, `user` `MAILPIT_SMTP_USER`, `password` `MAILPIT_SMTP_PASSWORD`, `starttls` `true` in dev / `false` on the demo host, `ssl` `false`); `verifyEmail` `true`; `resetPasswordAllowed` `true` in dev, `false` on the demo host; the administrator's `email` `admin@<INFRA_HOST>`, `emailVerified` `true`.
- No new setting nor secret: `.env` already holds `INFRA_HOST`, `MAILPIT_SMTP_USER`, `MAILPIT_SMTP_PASSWORD` and the bootstrap administrator's, in dev (`env.sh`) as on the demo host (`demo/write-env.sh`).

### User interface

None (the console's *Email* and *Login* tabs show the settings).

### Data

The master realm's settings and its administrator's address, in Keycloak's database, written once, when the realm is created.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| No password on a command line (`CLAUDE.md`) | REQ-6 |
| 0006 REQ-2: the registration account, nothing else in the master realm | REQ-7: no new right, no administrator's login (REQ-3) |
| README design | REQ-5 documents the re-creation |

## Points of attention

### PA-1 How the master realm gets its settings

- Issue: the registration account doesn't see the master realm's SMTP settings; an administrator's login at every start would, once the bootstrap administrator's password is changed, fail at every start, and with 0010's lockout lock that administrator out.
- Options: A an administrator logs in at every start / B the registration account reads the master realm's settings (`view-realm`), an administrator writes them / C they are written when the registration account is created or repaired
- Recommendation: B.
- Decides: tech lead
- Decision: neither: the master realm is pre-configured when it is created (the imported realm), and the configuration applies again only when the realm is re-created; the existing stacks get it by re-creating their Keycloak database (REQ-2, REQ-5). Departs knowingly from the intent's "the host already deployed included, with no manual step": the demo host already deployed needs that one re-creation. (Jérôme Wacongne, tech lead, 2026-10-23)

### PA-2 Settings to write and no administrator who logs in

- Issue: on the demo host without `KC_SETUP_ADMIN_*` once the bootstrap administrator is gone; in dev without a terminal.
- Options: A the start fails / B the start goes on with a warning
- Recommendation: B.
- Decides: product owner
- Decision: moot once PA-1 decided (no administrator's login); the administrator is pre-configured with `admin@<INFRA_HOST>` as its e-mail address (REQ-4). (Jérôme Wacongne, product owner, 2026-10-23)

### PA-3 *Forgot password* makes Mailpit's readers able to reset an administrator's password

- Issue: on the demo host, a reset mail for an administrator of the master realm lands in Mailpit, where whoever holds Mailpit's UI credentials reads it, and can then take over Keycloak, every application's realm included; with REQ-4, the administrator has an address.
- Options: A on everywhere, Mailpit's UI credentials the operators' only / B on in dev only / C on everywhere, the risk accepted
- Recommendation: A if no visitor is ever to read Mailpit, B otherwise.
- Decides: product owner, with the tech lead's agreement (high risk)
- Decision: B, *Forgot password* on in dev only (Jérôme Wacongne, product owner and tech lead, 2026-10-23)

### PA-4 *Verify email* and the stack's administrator logins

- Issue: an administrator whose address isn't verified has a pending action: Keycloak refuses their admin CLI login, which the stack (0006, REQ-3) and the tests use.
- Options: A accepted, documented, the stack's message naming the cause / B *Verify email* off in the master realm
- Recommendation: A.
- Decides: product owner
- Decision: A (Jérôme Wacongne, product owner, 2026-10-23)

### PA-5 The pre-configured address, verified or not

- Issue: with *Verify email* on (PA-4), an address `admin@<INFRA_HOST>` that isn't verified makes Keycloak refuse the administrator's admin CLI login from the first start: the first deployment can't create the registration account (0006), and the tests can't log in.
- Options: A marked verified by the pre-configuration (an address the operator chose, whose mails all land in Mailpit) / B left to verify: the operator verifies it from Mailpit before the stack's first administrator login, which fails until then
- Recommendation: A: B breaks the first deployment of every new host.
- Decides: product owner
- Decision: A, marked verified (Jérôme Wacongne, product owner, 2026-10-23)

## Acceptance criteria

- AC-1 Given a dev stack without its volumes, when `bash up.sh` runs, then the master realm has REQ-1's dev settings, *Verify email* and *Forgot password* on, and its administrator the verified address `admin@host.docker.internal`; its *Test connection* (the admin API's `testSMTPConnection`) delivers a mail that shows in Mailpit. (REQ-1, REQ-4, REQ-8, REQ-9)
- AC-2 Given the stand-in demo host on an empty database, when the deployment runs, then the same holds with the demo host's settings, *Forgot password* off, and the registration account is created. (REQ-1, REQ-4, REQ-8, REQ-9)
- AC-3 Given a master realm that exists, with other settings, when the stack starts, then nothing of it changes and no administrator logs in for it. (REQ-2, REQ-3)
- AC-4 Given the documented re-creation followed on a stack (the stand-in demo host), then its master realm has the configuration, the registration account is back, and a registration imports its realm again. (REQ-5)
- AC-5 Given the bootstrap administrator replaced and deleted, when the stack starts, then it succeeds and the master realm still delivers. (REQ-3)
- AC-6 Given `MAILPIT_SMTP_PASSWORD` changed and the documented step followed, then the master realm's *Test connection* delivers again. (REQ-5)
- AC-7 While Keycloak creates the realm, neither password is in the host's process list nor in the start's output, and the repository holds neither. (REQ-6)
- AC-8 Given the registration account, when it tries to change the master realm, then Keycloak still refuses. (REQ-7)
- AC-9 Given an administrator with an address, in dev, when *Forgot password?* is asked for on the master realm's login page, then the reset mail shows in Mailpit and its link sets a new password; on the demo host, the login page offers no *Forgot password?*. (REQ-8)
- AC-10 Given an administrator whose address isn't verified, when they log in to the console, then Keycloak asks them to verify it and the mail shows in Mailpit; their admin CLI login is refused until then, and the stack's message says why. (REQ-9)

## Intent questions

- *Suggested solution*: the stack sets the master realm's SMTP server itself, as an administrator, when it starts → not retained: the master realm is pre-configured when it is created (PA-1).

## Change log

- v1 — 2026-10-23 — first version; REQ-8 and REQ-9 (*Forgot password*, *Verify email*) added at the product owner's request after the intent's acceptance: beyond the intent's text, flagged, with PA-3 and PA-4
- v1 — 2026-10-23 — PA-1 to PA-4 decided (Jérôme Wacongne, product owner and tech lead): the master realm pre-configured when created (REQ-1 to REQ-5 rewritten), its administrator's address (REQ-4), *Forgot password* in dev only (REQ-8); PA-5 added, a consequence of REQ-4 and PA-4
- v1 — 2026-10-23 — approved: every point of attention decided (PA-5: the address marked verified); tech lead's agreement for the high risk (Jérôme Wacongne, PO and tech lead)
