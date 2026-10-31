# Spec: Nothing tells a visitor which applications are deployed, nor which account to sign in with

- Intent: [0048](intent.md)
- Status: draft
- Version: 1
- Risk: high (what a host exposes to the network: a new page at the infra host's root; authentication: accounts and passwords published, on the origin of Keycloak's administration console)
- Policies applied: none (the project has none yet)
- Approved: —

## Summary

The landing page the registrations already write in dev becomes the page of both environments, at the infra host's root: each registered application's name, linked to its host name in that environment, and the accounts it declared when it registered. An application declares its accounts in a small file given to its registration; nothing it declares can run on the page, which is served on Keycloak's origin.

## Requirements

- **RQ-01:** A registration takes an optional accounts file (`register-app.sh --accounts <file>` in dev, `sudo c4-app register --accounts <file>` on the demo host): one account per line, `<username> <password> [<label>…]`, blank lines and `#` comments ignored. Given, it replaces the application's list; absent, the list stays as it was; a file without an account line empties it. (intent: outcome, "kept up to date by the registrations")
- **RQ-02:** The registration refuses, naming the file, the line and the reason, and registering nothing, an accounts file with a field holding a control character or one of `<`, `>`, `&`, `"`, `'`, `` ` ``, a username or password holding a space, a line beyond 200 bytes, or more than 50 accounts. (intent: constraint, the Keycloak origin)
- **RQ-03:** The page lists, for each application the environment registered (a site of its own), its name, linked to `https://<its host name in this environment>/` (the registry's dev host in dev, its demo host on the demo host), then its accounts in the file's order: username, password, label. It needs no translation: no text but the names, the accounts and the page's title, `c4-infra`; in dev, the shared services' links stay above the applications, as today. (intent: outcome, decided at acceptance)
- **RQ-04:** Every value the page shows is escaped for HTML, although RQ-02 already refuses what would need it. (intent: constraint, the Keycloak origin)
- **RQ-05:** The page is served at the infra host's root (`/`) in both environments, with a content security policy that allows no script, no form, no frame and no external resource, and asks search engines not to index it (a header and a `meta`). Every other path of the infra host answers as today. (intent: constraint; what a host exposes)
- **RQ-06:** The page is written again by each registration, by `register-app.sh --index-only`, by `up.sh` in dev when it is missing (as today), and by each deployment of the stack on the demo host, so that a change of the page's form reaches it without a registration. (intent: outcome, "kept up to date")
- **RQ-07:** The README ("What an application provides", and the demo host's deployment) and `docs/migration.md` say how an application declares its accounts, and that only accounts that exist for the demo, with a password used nowhere else, may be declared. (intent: constraint, decided at acceptance)

## Out of scope

- Each application's accounts file and the option in its deployment (Faito, Tickee: their repositories).
- Setting or rotating an application's passwords (PA-01's option B, if chosen, becomes its own intent).
- Links to the shared services on the demo host (Mailpit, Grafana: the Demo operator's, behind their own credentials).

## Design

### Current behaviour

- `register-app.sh:112-134` (`write_index`, dev only: `[ "$INFRA_ENV" = dev ] || return 0`) writes `caddy/html/index.html`: the shared services' links, then one link per `caddy/apps/*.caddy` to its registry dev host; run by each registration (`:634`), by `--index-only` (`:136-138`), and by `up.sh` when the file is missing (`up.sh:85`). `caddy/env/dev.caddy` serves it at `/` (`file_server`, `/etc/caddy/html`); no security header but the common ones.
- On the demo host, the infra host's last `handle` answers `404` "c4-infra: the applications are on their own host names" (`caddy/Caddyfile`), asserted at `/` by `tests/0003-demo-edge.sh:129`. The deployment copies its files without `--delete` (`.github/workflows/deploy-demo.yml:182`): a page written on the host stays across deployments.
- `sudo c4-app register` accepts `--realm`, `--themes`, `--proxy`, `--rabbitmq-user`, `--rabbitmq-password-env`, `--reset-realms` and refuses any other option (`demo/c4-app:547-575`); the files it hands root are staged copies (`staged_path`).
- The accounts can't be read from what is registered: Faito's two users and Tickee's `brasserie` and `tenant3` users hold password hashes; Tickee's `tenant2` reads its users from an LDAP directory in `READ_ONLY` mode, its `tickee` realm brokers the four others (exports read on 2026-10-30).
- The repositories of the deployed applications are private (Tickee, Faito, GitHub, 2026-10-30): a workflow's logs and summaries are read by their collaborators only. Their deployments run on a push to their deployment branch: no pull request is involved.

### Behaviour per persona

- **Demo visitor:** opens `https://infra.c4-soft.com/`, sees each application's name as a link and its accounts, follows a link, signs in.
- **Developer:** the same page at `https://host.docker.internal/`, with the shared services' links above.
- **Application:** adds `--accounts <file>` to its registration, in dev and in its demo workflow; a refused file stops the registration with RQ-02's message.

### API and contracts

- Option `--accounts <file>` of `register-app.sh` and of `sudo c4-app register` (RQ-01, RQ-02).
- The page (RQ-03, RQ-05), e.g.:

  ```text
  c4-infra
  tickee                       (link: https://tickee.c4-soft.com/)
    brasserie1.manager1   <password>   brasserie 1, manager
    tenant2.worker2       <password>   tenant 2, worker
  faito                        (link)
    …
  ```

### User interface

A plain page: one heading per application (its name, a link), one row per account (username, password, label), monospace for the first two; inline styles only, readable on a phone; no image, no script.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| — | the project has no policy yet; README's design (one origin per application, the infra host for the shared services) → RQ-05, PA-02 |

## Points of attention

### PA-01: Where a visitor finds the passwords

- Issue: the product owner accepted publishing the accounts, and asked to study a password generated at each deployment and shown by the application's CI instead.
- Options:
  - **A** the page shows each account's password, fixed by the application (what was accepted);
  - **B** on the demo host, the page lists the accounts without passwords; each registration draws a new password for each listed account and sets it in the application's realm, and the application's workflow writes them into its run's summary, which only the repository's collaborators read (the repositories are private). Its limits, read in README ("The registration account") and the exports: the registration account may set the password of a realm's own users, not of users an LDAP directory holds read-only (Tickee's `tenant2`, which Tickee would have to set itself); every deployment changes every password, so a demo prepared before a push no longer signs in with the password sent; no pull request exists to comment on. It also needs an option that draws and sets passwords, and each application's workflow to publish them;
  - **C** the page shows the passwords but, on the demo host, asks for one password of its own first (as Mailpit does), a secret of the `demo` environment, given by the product owner to whoever should see it.
- Recommendation: A: the demo host can be reset at any time and only accounts made for it are listed (RQ-07), and the page asks not to be indexed; B protects more but doesn't cover Tickee's directory and breaks a prepared demo at each push; C hides the page for one secret more to hand out. B or C stay possible later, as their own intent.
- Decides: PO
- Decision: to decide

### PA-02: The page on Keycloak's origin

- Issue: the infra host is the origin of Keycloak and its administration console (`/auth/`): a script that ran on the page could act with an administrator's session.
- Options: **A** at the infra host's root, with RQ-02's refusals, RQ-04's escaping and RQ-05's policy that allows no script / **B** on a host name of its own (a DNS record and a certificate on the demo host, a site of the reverse proxy), an origin apart from Keycloak's.
- Recommendation: A: three independent barriers, and no DNS record for the Demo operator to add; B would make sense if the page ever needed a script.
- Decides: PO
- Decision: to decide

### PA-03: The simulated providers' accounts

- Issue: the stack's own default accounts (`simulated-google`, `simulated-facebook`, `simulated-apple`: `alice`, `bob`, `carol`, `relay`, README "Simulated social providers", already public) let a visitor try an application's "Sign in with …".
- Options: **A** listed on the page as three more entries, each named after its realm, without a link / **B** left out: only the applications.
- Recommendation: A: an application that offers those buttons on the demo host can't be tried without them, and they are public already.
- Decides: PO
- Decision: to decide

## Acceptance criteria

- **AC-01:** Given the dev stack and an application registered with an accounts file of two accounts, one with a label holding a space and an accented letter, when `https://host.docker.internal/` is fetched, then it lists the shared services, then the application's name linked to its dev host, then both accounts in order, with their passwords (PA-01 A). (RQ-01, RQ-03, RQ-06)
- **AC-02:** Given a stand-in demo host and an application registered by `sudo c4-app register --accounts <file>`, when `https://infra.<domain>/` is fetched over HTTPS, then it answers `200` with the application's name linked to its demo host and its accounts, a content security policy without script, and `X-Robots-Tag: noindex`; `/rabbitmq/` and an unknown path still answer `404`. (RQ-03, RQ-05)
- **AC-03:** Given an accounts file with `<script>` in a label, `"` in a password, a space in a username, a 201-byte line or 51 accounts, when the application registers, then the registration is refused naming the file, the line and the reason, nothing is registered, and the page is unchanged. (RQ-02)
- **AC-04:** Given an application registered with accounts, when it registers again without `--accounts`, then the page still lists them; with a file of comments only, then its link stays and no account. (RQ-01)
- **AC-05:** Given a page written before a change of its form, when the stack is deployed on the stand-in, then the page has the new form without any registration. (RQ-06)
- **AC-06:** Given the escaping, when a value holding `&` reaches the page through a test of the writer alone, then the page holds `&amp;`. (RQ-04)
- **AC-07:** Given the README and the migration guide, then they say how to declare the accounts and the rule of RQ-07. (RQ-07)

## Intent questions

- A random password per deployment shown by the CI → PA-01 (option B, studied).

## Change log

- v1 — 2026-10-30 — first version
