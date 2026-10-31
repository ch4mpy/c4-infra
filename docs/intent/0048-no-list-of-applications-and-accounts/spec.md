# Spec: Nothing tells a visitor which applications are deployed, nor which account to sign in with

- Intent: [0048](intent.md)
- Status: approved
- Version: 2
- Risk: high (what a host exposes to the network: a new page at the infra host's root; authentication and secrets: the demo accounts' passwords, drawn and kept on the demo host, set in the applications' realms; the page on the origin of Keycloak's administration console)
- Policies applied: none (the project has none yet)
- Approved: v1 2026-10-30, Jérôme Wacongne (product owner, also tech lead), in the drafting session, every point of attention decided; v2 2026-10-30, the same, with the batch's plan (its section "0048 spec v2")

## Summary

The landing page the registrations already write in dev becomes the page of both environments, at the infra host's root. Each registered application has a section: its name, linked to its host name in that environment; a `users` subsection, the accounts it declared when it registered, `<username> [<group>, …]`; a `groups` subsection, those users' groups and their roles, `<group> [<role>, …]`, as Keycloak held them at that registration. On the demo host the page shows no password: the registration draws one for each declared account, keeps it, sets it in the application's realm, and gives it to the application's own account only, for its workflow to publish where only the project's members read it (a comment of the pull request it deploys). In dev, the page shows the password the application declares. Nothing an application declares or names in Keycloak can run on the page, which is served on Keycloak's origin.

## Requirements

- **RQ-01:** A registration takes an optional accounts file (`register-app.sh --accounts <file>` in dev, `sudo c4-app register --accounts <file>` on the demo host): one account per line, `<realm> <username> <dev password>`, the dev password `-` when none is shown, blank lines and `#` comments ignored; `<realm>` is one of the application's realms in the registry. Given, it replaces the application's list; absent, the list stays as it was; a file without an account line empties it. (intent: outcome, "kept up to date by the registrations"; v2: no label, the groups come from Keycloak)
- **RQ-02:** The registration refuses, naming the file, the line and the reason, and registering nothing, an accounts file with a field holding a control character or one of `<`, `>`, `&`, `"`, `'`, `` ` ``, a line of other than three fields, a realm that isn't the application's, a line beyond 200 bytes, or more than 50 accounts. (intent: constraint, the Keycloak origin)
- **RQ-03:** The page has, for each application the environment registered (a site of its own), a section: its name, linked to `https://<its host name in this environment>/` (the registry's dev host in dev, its demo host on the demo host); a `users` subsection, one line per declared account in the file's order, `<username> [<group>, …]` on the demo host, never a password, `<username> <dev password> [<group>, …]` in dev (no password shown for `-`); a `groups` subsection, one line per group of those users, `<group> [<role>, …]`: the group's own realm roles, then its client roles as `<client>:<role>`, each list sorted. A group is shown by its path, prefixed by `<realm>/` when the application's accounts span several realms. The page needs no translation: no text but the names, the accounts, the subsections' names and its title, `c4-infra`; in dev, the shared services' links stay above the applications, as today. (intent: outcome, decided at acceptance; PA-01; the product owner's v2)
- **RQ-04:** Every value the page shows is escaped for HTML: those of the accounts file, although RQ-02 already refuses what would need it, and those read from Keycloak (group, role and client names), which nothing filters. (intent: constraint, the Keycloak origin)
- **RQ-05:** The page is served at the infra host's root (`/`) in both environments, with a content security policy that allows no script, no form, no frame and no external resource, and asks search engines not to index it (a header and a `meta`). Every other path of the infra host answers as today. (intent: constraint; what a host exposes)
- **RQ-06:** The page is written again by each registration, by `register-app.sh --index-only`, by `up.sh` in dev when it is missing (as today), and by each deployment of the stack on the demo host, so that a change of the page's form reaches it without a registration. (intent: outcome, "kept up to date")
- **RQ-07:** On the demo host, each declared account has a password the registration draws (24 characters at least, with lowercase and uppercase letters, digits and a non-alphanumeric character), kept on the host where root alone reads it, and set in Keycloak for that user at each registration that gives `--accounts`, so that the same password signs in from one deployment to the next and a realm imported again gets it back. A password is drawn for an account the host doesn't hold yet, and for every account with `sudo c4-app register --new-passwords`; the dev password the file gives is never used there. (PA-01 B)
- **RQ-08:** An account whose password Keycloak doesn't set (a user its realm doesn't have, a user an LDAP directory holds read-only) stops the registration, exit status non-zero, naming the account and Keycloak's answer; the page isn't written. (PA-01 B; the constraint "only accounts that exist for the demo")
- **RQ-09:** `sudo c4-app accounts`, run as an application's account, prints that application's accounts with their current passwords, one per line, `<realm> <username> <password>`, for its workflow to publish; no other output of the stack holds a drawn password (not the registration's, not a log, not the page). (PA-01 B)
- **RQ-10:** In dev, no password is drawn nor set: the realm's own users keep the passwords the application gave them. (decided at acceptance: the page in dev; PA-01 B is the demo host's)
- **RQ-11:** The README ("What an application provides", the demo host's deployment) and `docs/migration.md` say how an application declares its accounts, that only accounts made for the demo may be declared, and how its workflow publishes their passwords: `sudo c4-app accounts` read into a variable, each password masked in the run's log, then a comment on the pull request whose merge the run deploys (`GET /repos/{owner}/{repo}/commits/{sha}/pulls`), or the run's summary when there is none (a manual run, a direct push), with the permission that needs. (PA-01 B)
- **RQ-12:** The users' groups and the groups' roles are read from Keycloak by the registration that gives `--accounts`, after its realms are imported and, on the demo host, its passwords set, and kept until the next such registration: the page describes the state of that registration, and doesn't follow later changes made in Keycloak. (the product owner's v2)

## Out of scope

- Each application's accounts file and the step of its workflow that publishes the passwords (Tickee, Faito: their repositories; RQ-11 gives the example).
- The passwords of users an LDAP directory holds read-only (Tickee's `tenant2`): the application's own, which it leaves out of its file or sets itself (RQ-08).
- A user's roles mapped to the user directly, not through a group; a group's composite roles expanded.
- Links to the shared services on the demo host (Mailpit, Grafana: the Demo operator's, behind their own credentials).

## Design

### Current behaviour

- `register-app.sh:112-134` (`write_index`, dev only: `[ "$INFRA_ENV" = dev ] || return 0`) writes `caddy/html/index.html`: the shared services' links, then one link per `caddy/apps/*.caddy` to its registry dev host, values not escaped; run by `--index-only` (`:136-138`), by a registration only when its site changed (`:634`), and by `up.sh` when the file is missing (`up.sh:85`). `caddy/env/dev.caddy` serves it at `/` (`file_server`, `/etc/caddy/html`); no security header but the common ones.
- On the demo host, the infra host's last `handle` answers `404` "c4-infra: the applications are on their own host names" (`caddy/Caddyfile`), asserted at `/` by `tests/0003-demo-edge.sh:129`. The deployment copies its files without `--delete` (`.github/workflows/deploy-demo.yml:182`): a page written on the host stays across deployments.
- `sudo c4-app register` accepts `--realm`, `--themes`, `--proxy`, `--rabbitmq-user`, `--rabbitmq-password-env`, `--reset-realms` and refuses any other option (`demo/c4-app:547-575`); the files it hands root are staged copies (`staged_path`); every run wipes its working copy (`copy_in`), so nothing root keeps survives it there.
- The registration account manages every realm of the registry (every role of the master realm's client `<realm>-realm`: README, "The registration account"), so it may read a realm's users, groups and roles and set a user's password there; it can't for a user of a read-only federation: Keycloak holds no password for it.
- The accounts can't be read from what is registered: Faito's two users and Tickee's `brasserie` and `tenant3` users hold password hashes; Tickee's `tenant2` reads its users from an LDAP directory in `READ_ONLY` mode, its `tickee` realm brokers the four others; no realm of theirs has a password policy (exports read on 2026-10-30).
- The repositories of the deployed applications are private (Tickee, Faito, GitHub, 2026-10-30): a pull request's comments and a run's summary are read by their collaborators only. Tickee's deployment runs on a push to `master`, a pull request's merge, and by hand (`workflow_dispatch`) (its `.github/workflows/deploy-demo.yml`).

### Behaviour per persona

- **Demo visitor:** opens `https://infra.c4-soft.com/`, sees each application's name as a link, its users and their groups, the groups and their roles; gets a password from a member of the project.
- **Project member** (an application's collaborator): reads the passwords in the comment the deployment left on the merged pull request, or in the run's summary.
- **Developer:** the same page at `https://host.docker.internal/`, with the shared services' links above, and the dev passwords.
- **Application:** adds `--accounts <file>` to its registration in dev and in its demo workflow, and the publishing step to the latter (RQ-11); a refused file or an account Keycloak can't set stops the registration (RQ-02, RQ-08).

### API and contracts

- Options `--accounts <file>` of `register-app.sh` and of `sudo c4-app register`; `--new-passwords` of `sudo c4-app register` (RQ-01, RQ-02, RQ-07).
- Subcommand `sudo c4-app accounts` (RQ-09).
- The page (RQ-03, RQ-05), e.g. on the demo host:

  ```text
  c4-infra
  tickee                                   (link: https://tickee.c4-soft.com/)
    users
      brasserie1.manager1   [brasserie/managers]
      tenant3.worker3       [tenant3/workers]
    groups
      brasserie/managers    [manager, tickee-api:read]
      tenant3/workers       [worker]
  simulated-google
    users
      alice
      bob
  ```

### User interface

A plain page: one heading per application (its name, a link), its `users` and `groups` subsections, usernames and group paths in monospace; inline styles only, readable on a phone; no image, no script.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| — | the project has no policy yet; README's design (one origin per application, the infra host for the shared services) → RQ-05, PA-02; "no password on a command line" (CLAUDE.md) → the drawn passwords reach Keycloak's CLI on its standard input |

## Points of attention

### PA-01: Where a visitor finds the passwords

- Issue: the product owner accepted publishing the accounts, and asked to study a password generated at each deployment and shown by the application's CI instead.
- Options:
  - **A** fixed passwords, drawn once by the application, in a file of its private repository, which the page links to (GitHub answers 404 to a non-member);
  - **B** on the demo host, the registration draws each account's password, keeps it stable on the host and sets it again at each registration; the application's workflow publishes it in a comment of the pull request it deploys (the run's summary when there is none), which only the repository's collaborators read; the page shows no password. Limits: Keycloak can't set a password an LDAP directory holds read-only (Tickee's `tenant2`); each application adds the publishing step to its workflow.
- Recommendation: A, for its lower cost; B keeps every password out of git.
- Decides: PO
- Decision: B (the product owner, 2026-10-30: "le mot de passe serait plutôt sur une page de PR GitHub accessible uniquement aux membres du projet"), with stable passwords drawn by the registration; the public page's lines without password (the product owner, the same day, then v2's subsections).

### PA-02: The page on Keycloak's origin

- Issue: the infra host is the origin of Keycloak and its administration console (`/auth/`): a script that ran on the page could act with an administrator's session.
- Options: **A** at the infra host's root, with RQ-02's refusals, RQ-04's escaping and RQ-05's policy that allows no script / **B** on a host name of its own (a DNS record and a certificate on the demo host, a site of the reverse proxy), an origin apart from Keycloak's.
- Recommendation: A: three independent barriers, and no DNS record for the Demo operator to add; B would make sense if the page ever needed a script.
- Decides: PO
- Decision: A (the product owner, 2026-10-30)

### PA-03: The simulated providers' accounts

- Issue: the stack's own default accounts (`simulated-google`, `simulated-facebook`, `simulated-apple`: `alice`, `bob`, `carol`, `relay`, README "Simulated social providers", where their passwords are public) let a visitor try an application's "Sign in with …".
- Options: **A** listed on the page as three more sections, each named after its realm, without a link / **B** left out: only the applications.
- Recommendation: A: an application that offers those buttons on the demo host can't be tried without them, and they are public already.
- Decides: PO
- Decision: A (the product owner, 2026-10-30): a `users` subsection only (they have no group), their public password in dev only, as the applications' (RQ-03).

## Acceptance criteria

- **AC-01:** Given the dev stack and an application registered with a realm of two users in two groups, one group with a realm role and a client role, and an accounts file declaring both users, when `https://host.docker.internal/` is fetched, then it lists the shared services, then the application's name linked to its dev host, its `users` subsection (each username, its dev password, its group) and its `groups` subsection (each group, its sorted roles, the client role as `<client>:<role>`); no password of the realm changed. (RQ-01, RQ-03, RQ-06, RQ-10, RQ-12)
- **AC-02:** Given a stand-in demo host and an application registered by `sudo c4-app register --accounts <file>`, when `https://infra.<domain>/` is fetched over HTTPS, then it answers `200` with the application's name linked to its demo host, its `users` and `groups` subsections, no drawn password and no dev password anywhere in it, a content security policy without script, and `X-Robots-Tag: noindex`; `/rabbitmq/` and an unknown path still answer `404`. (RQ-03, RQ-05)
- **AC-03:** Given an accounts file with `<script>` in a username, `"` in a dev password, a line of two fields, another application's realm, a 201-byte line or 51 accounts, when the application registers, then the registration is refused naming the file, the line and the reason, nothing is registered, and the page is unchanged. (RQ-02)
- **AC-04:** Given an application registered with accounts, when it registers again without `--accounts`, then the page still lists them; with a file of comments only, then its link stays and no account. (RQ-01)
- **AC-05:** Given a page written before a change of its form, when the stack is deployed on the stand-in, then the page has the new form without any registration. (RQ-06)
- **AC-06:** Given the fixture realm's group whose name holds `&` and `<`, when the application registers with its accounts, then the page holds the name escaped (`&amp;`, `&lt;`), and no element the name would have opened. (RQ-04)
- **AC-07:** Given a stand-in demo host and an application registered with two accounts, when its account runs `sudo c4-app accounts`, then each line's password signs in to its realm (a password grant) and meets RQ-07's form; a second registration keeps both passwords; with `--new-passwords`, both change and the old ones no longer sign in; another application's account sees only its own; the registration's output holds no password. (RQ-07, RQ-09)
- **AC-08:** Given an accounts file naming a user its realm doesn't have, when the application registers on the stand-in, then the registration stops non-zero naming that account and Keycloak's answer, and the page isn't written. (RQ-08)
- **AC-09:** Given the README and the migration guide, then they say how to declare the accounts, the rule that only demo accounts are declared, and the workflow step of RQ-11. (RQ-11)
- **AC-10:** Given an application registered with accounts, when one of its users is then added to another group in Keycloak, then the page is unchanged until the application's next registration with `--accounts`, which shows it. (RQ-12)

## Intent questions

- A random password per deployment shown by the CI → PA-01 B: drawn by the registration, kept stable, published by the application's workflow on its pull request.

## Change log

- v1 — 2026-10-30 — first version
- v1 — 2026-10-30 — PA-01 decided B (the passwords off the public page, on the deployed pull request), the public line `<username> [<role or group>]`: RQ-01 and RQ-03 rewritten, RQ-07 to RQ-10 added, RQ-07 (the docs) renumbered RQ-11; AC-07 to AC-09 rewritten; approved, every point decided
- v2 — 2026-10-30 — the product owner's request: each application's section has a `users` subsection (`<username> [<group>, …]`) and a `groups` subsection (`<group> [<role>, …]`), read from Keycloak at the registration, a snapshot that doesn't follow later changes; RQ-01 (no label), RQ-02 (three fields), RQ-03, RQ-04 (Keycloak's values escaped), RQ-09 (`<realm> <username> <password>`) rewritten, RQ-12 added; AC-01, AC-02, AC-03, AC-06 rewritten, AC-10 added; PA-03's decision follows (a `users` subsection only); approved with the batch's plan
