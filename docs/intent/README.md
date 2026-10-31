# Intents

Stage 1 (Plan) of the [AI-native SDLC](https://claude.com/resources/articles/the-ai-native-sdlc-playbook): every change starts as an **intent**, a short statement of a need that the product owner accepts or rejects before anyone specifies, plans or codes it.

One folder per change, numbered: `NNNN-<slug>/` holds `intent.md`, then `spec.md` (Stage 2) and `plan.md` (Stage 3). An accepted intent is never rewritten: a changed need is a new intent that supersedes it.

**One branch per intent.** A change lives on a single branch, `NNNN-<slug>`, with a single draft PR, from its draft to its delivery: intent, spec, plan and code are committed on it, and it reaches the base branch once, merged by a human just before deployment. Each gate leaves a status commit, a PR comment naming the decider, and moves the PR's label (`stage:intent` → `stage:spec` → `stage:plan` → `stage:build` → `stage:review`). The index below lists what reached the base branch; **work in progress is the open PRs with a `stage:*` label, plus the intents of the index that are `accepted`, `specified` or `planned` without a PR** (bootstrap mode, below).

**Bootstrap mode.** Until the project's first production release, the `Mode` line of the project context can say `bootstrap`: one person decides everything, so the skills drop the team ceremony and keep every rule that makes the code good. An intent is written already accepted, its spec is approved in the session that drafts it once read and its points of attention decided, the plan stays an explicit step in plan mode, and the work lands on the base branch without a PR (a branch only when another intent is in progress); a change is verified once, its evidence kept in `plan.md`, pushes are not confirmed, and the release gate does not hold pushes to the base branch. Each intent keeps the mode it started in (its `Mode` field). The first production release (`/sdlc-ship`) sets the line to `normal`; the product owner may edit it by hand; the agent never sets it to `bootstrap`, except when it creates the intent home, with the product owner's confirmation.

## Project context

<!-- Read by the sdlc-* skills. Keep it short and up to date. -->

- Language: English
- Personas and roles:
  - **Developer**: runs one or more applications on a workstation, on top of the dev stack;
  - **Demo operator**: sets up and runs the demo host (VPS, DNS, GitHub environment and secrets);
  - **Application**: a project that registers with the stack (Faito, Hurura'a, Tickee, Turu…), its deployment scripts and workflows;
  - **Demo visitor**: anyone using an application on the public demo host.
- Modules / systems: shared stack (`compose.yml` with `compose.dev.yml` or `compose.demo.yml`, `up.sh`, `env.sh`), reverse proxy (`caddy/`, `routes.sh`), demo host (`demo/`: `c4-app`, `deploy.sh`, `vps-bootstrap.sh`), registration (`register-app.sh`, `registration-account.sh`, `networks.sh`, `export-realm.sh`, `new-realm-ids.sh`), registry (`registry.txt`, `registry.sh`), certificates (`certs/`), deployment workflow (`.github/workflows/`)
- Standing constraints: the design section of [README.md](../../README.md); the decision that created this stack, [Faito's decision 0001](https://github.com/ch4mpy/faito/blob/main/docs/decisions/0001-infra-partagee.md) (one origin per application, Keycloak on PostgreSQL, `infra.c4-soft.com`)
- Base branch: main
- Mode: bootstrap (c4-infra is never a production environment: the product owner, 2026-10-30)
- Product owner(s): Jérôme Wacongne (also tech lead)
- Intent template: [_intent-template.md](_intent-template.md)
- Policies: none yet
- Tech lead: Jérôme Wacongne
- Spec template: [_spec-template.md](_spec-template.md)
- Identifiers: requirements as list items `**RQ-01:**`, acceptance criteria `**AC-01:**`, invariants `**IV-01:**`, points of attention as headings `### PA-01: <title>`; the plain identifier in the first cell of a table row, and plain `RQ-01` wherever an element is cited; numbers run from `01` to `99` in order of appearance and are never reassigned by a later version of the spec (a spec that needs more than 99 of a kind is too big: split the intent); a new kind of element takes a new two-letter prefix, declared on this line
- Plan template: [_plan-template.md](_plan-template.md)
- Risk rules: a spec is high-risk if it touches authentication, authorization or secrets, the isolation between applications, what a host exposes to the network, or personal data; standard otherwise
- Status vocabulary:

  | Key | Label | Set by |
  | --- | --- | --- |
  | proposed | proposed | Stage 1, when the intent's PR is opened |
  | accepted | accepted | the product owner (status commit, PR comment, label `stage:spec` or `stage:plan`) |
  | rejected | rejected | the product owner (PR closed, never on the base branch) |
  | specified | specified | Stage 2, once `spec.md` is approved |
  | planned | planned | Stage 3, once `plan.md` is approved |
  | delivered | delivered | Stage 5, just before the merge that deploys it |
  | abandoned | abandoned | superseded by another intent, or dropped |

## How to propose and decide

- **Propose**: open an issue with the intent form, or run `/sdlc-intent draft <idea>` (or `draft #<issue>`). The intent arrives as a draft PR labelled `stage:intent`, on its own branch `NNNN-<slug>`.
- **Decide** (product owner): `/sdlc-intent accept <NNNN>` records the acceptance on the branch (nothing is merged); `/sdlc-intent reject <NNNN> <reason>` closes the PR with the reason.
- **Measure**: `/sdlc-intent stats`.

## Index

| No. | Intent | Kind | Status | Opened | Decided |
| --- | --- | --- | --- | --- | --- |
| 0001 | [The dev stack is reachable from the local network](0001-dev-stack-reachable-from-the-network/intent.md) | bug | delivered | 2026-10-21 | 2026-10-21 |
| 0002 | [Deploying to the demo host gives every application's workflow the whole host](0002-demo-deployment-access/intent.md) | change | delivered | 2026-10-21 | 2026-10-21 |
| 0003 | [Dev doesn't apply the demo's reverse-proxy rules](0003-dev-and-demo-proxies-diverge/intent.md) | change | delivered | 2026-10-21 | 2026-10-21 |
| 0004 | [Nothing prevents two applications from taking the same port block](0004-port-registry-unchecked/intent.md) | change | delivered | 2026-10-21 | 2026-10-21 |
| 0005 | [A theme change restarts the Keycloak every application uses](0005-theme-change-restarts-keycloak/intent.md) | change | delivered | 2026-10-21 | 2026-10-21 |
| 0006 | [Registrations depend on Keycloak's temporary bootstrap administrator](0006-registration-uses-bootstrap-admin/intent.md) | bug | delivered | 2026-10-21 | 2026-10-21 |
| 0007 | [On the demo host, an application's containers reach every shared service and every other application](0007-demo-containers-reach-every-service/intent.md) | bug | delivered | 2026-10-21 | 2026-10-21 |
| 0008 | [c4-infra's certificate scripts spread the local CA's private key and its password](0008-certificate-scripts-spread-the-ca-key/intent.md) | bug | delivered | 2026-10-22 | 2026-10-22 |
| 0009 | [Keycloak's master realm sends no mail](0009-master-realm-sends-no-mail/intent.md) | bug | delivered | 2026-10-23 | 2026-10-23 |
| 0010 | [No realm of the shared Keycloak protects its accounts against password guessing](0010-no-brute-force-protection/intent.md) | change | delivered | 2026-10-23 | 2026-10-23 |
| 0011 | [The demo host builds images the applications' CI already builds, and some stack scripts misreport errors](0011-demo-builds-and-script-errors/intent.md) | bug | delivered | 2026-10-23 | 2026-10-23 |
| 0012 | [An application's Keycloak theme may read the shared Keycloak's environment](0012-themes-read-keycloak-environment/intent.md) | bug | delivered | 2026-10-23 | 2026-10-23 |
| 0013 | [The shared stack lacks what Turu and Hurura'a need to move onto it](0013-stack-lacks-what-turu-and-hururaa-need/intent.md) | change | delivered | 2026-10-23 | 2026-10-23 |
| 0015 | [The shared proxy imposes its security headers on every application's front end](0015-proxy-imposes-front-end-headers/intent.md) | change | delivered | 2026-10-26 | 2026-10-27 |
| 0016 | [The shared Keycloak offers no simulated Google, Facebook or Apple provider to try a social login](0016-no-simulated-google-and-apple-realms/intent.md) | change | delivered | 2026-10-26 | 2026-10-27 |
| 0017 | [The verification runs every test every time, and says nothing of where its time goes](0017-suite-runs-every-test-every-time/intent.md) | change | delivered | 2026-10-27 | 2026-10-27 |
| 0018 | [The registry test requires exactly four applications, so registering a new one fails the verification](0018-registry-test-pins-four-entries/intent.md) | bug | delivered | 2026-10-27 | 2026-10-27 |
| 0019 | [The stand-in deployment test fails on a workstation whose locale isn't C](0019-stand-in-test-depends-on-locale/intent.md) | bug | delivered | 2026-10-28 | 2026-10-28 |
| 0020 | [The isolation test's probe image fails to build in the stand-in, now and then, on a DNS error](0020-stand-in-probe-build-dns/intent.md) | bug | delivered | 2026-10-28 | 2026-10-28 |
| 0022 | [A full verification runs its stand-in tests one after the other, while nothing else runs](0022-full-verification-runs-sequentially/intent.md) | change | delivered | 2026-10-28 | 2026-10-28 |
| 0023 | [The stack still documents and tests an LDAP user federation no application needs](0023-ldap-leaves-the-stack/intent.md) | change | delivered | 2026-10-28 | 2026-10-28 |
| 0024 | [A deployment that pulls a new database image recreates the database under a running Keycloak, and the registration check then blames the administrator](0024-database-image-change-under-keycloak/intent.md) | bug | delivered | 2026-10-28 | 2026-10-28 |
| 0025 | [A refused `sudo c4-app up` or `pull` still copies the refused files where the application's running containers read them](0025-refused-deployment-still-staged/intent.md) | bug | delivered | 2026-10-28 | 2026-10-28 |
| 0026 | [The demo host doesn't bound the logs of an application's containers](0026-demo-host-bounds-no-application-logs/intent.md) | change | delivered | 2026-10-28 | 2026-10-28 |
| 0027 | [The demo host backs up no application's data](0027-demo-host-backs-up-no-application-data/intent.md) | change | delivered | 2026-10-28 | 2026-10-28 |
| 0028 | [The migration guide misleads a project on its demo ports, the images it may run and its CI's platform](0028-migration-guide-misleads-on-demo-ports-images-ci/intent.md) | change | delivered | 2026-10-28 | 2026-10-28 |
| 0029 | [An application can't tell which Keycloak its tests should run](0029-applications-cannot-tell-which-keycloak-to-test/intent.md) | change | delivered | 2026-10-28 | 2026-10-28 |
| 0030 | [new-realm-ids.sh leaves a user federation component's id as it was](0030-new-realm-ids-keeps-federation-component-ids/intent.md) | bug | delivered | 2026-10-28 | 2026-10-28 |
| 0031 | [No test proves that a front end's own Permissions-Policy reaches the browser unchanged](0031-front-end-own-permissions-policy-untested/intent.md) | change | delivered | 2026-10-28 | 2026-10-28 |
| 0032 | [The migration guide offers a GitLab CI job the demo host doesn't serve](0032-migration-guide-offers-gitlab-ci-demo-doesnt-serve/intent.md) | change | delivered | 2026-10-28 | 2026-10-28 |
| 0033 | [A demo host backup cut by its time limit may leave its dump running, a restore has no time limit, and four backup paths are untested](0033-backup-timeout-leaves-dump-running/intent.md) | bug | delivered | 2026-10-28 | 2026-10-28 |
| 0034 | [tests/0007-dev.sh's isolation checks pass when the application's network doesn't exist](0034-isolation-checks-pass-without-network/intent.md) | bug | delivered | 2026-10-28 | 2026-10-28 |
| 0035 | [The stand-in demo host can't serve an application over HTTPS](0035-stand-in-demo-host-has-no-https/intent.md) | change | delivered | 2026-10-28 | 2026-10-28 |
| 0036 | [A change of the stack's Keycloak doesn't say that an application's generated admin client moves with it](0036-keycloak-change-silent-on-admin-client/intent.md) | change | delivered | 2026-10-29 | 2026-10-29 |
| 0037 | [A run waiting for the suite's lock can be overtaken by later runs, without bound](0037-suite-lock-has-no-queue/intent.md) | bug | delivered | 2026-10-29 | 2026-10-29 |
| 0038 | [tests/0029-description.sh's carriage-return check fails under Git Bash on a description without one](0038-description-test-cr-check-fails-under-git-bash/intent.md) | bug | delivered | 2026-10-29 | 2026-10-30 |
| 0039 | [Four Keycloak tests fail under Git Bash on the Windows workstation: the native jq and curl can't reach their files](0039-keycloak-tests-fail-under-git-bash/intent.md) | bug | delivered | 2026-10-30 | 2026-10-30 |
| 0040 | [The first deployment of the stack after an application's first registration recreates the shared services](0040-shared-services-recreated-after-first-registration/intent.md) | change | delivered | 2026-10-30 | 2026-10-30 |
| 0041 | [register-app.sh replaces an application's brute-force settings with the stack's, without a word](0041-brute-force-settings-replaced-silently/intent.md) | change | delivered | 2026-10-30 | 2026-10-30 |
| 0042 | [The migration guide describes Tickee as it was before its migration](0042-migration-guide-tickee-section-stale/intent.md) | change | delivered | 2026-10-30 | 2026-10-30 |
| 0043 | [An application's registration fails while another registered application's network is gone](0043-registration-fails-without-another-apps-network/intent.md) | bug | delivered | 2026-10-30 | 2026-10-30 |
| 0044 | [The registry's test pins the applications' real entries](0044-registry-test-pins-live-entries/intent.md) | change | delivered | 2026-10-30 | 2026-10-30 |
| 0045 | [The registry demands a demo host of an application the demo host never deploys](0045-registry-demands-a-demo-host/intent.md) | change | delivered | 2026-10-30 | 2026-10-30 |
| 0046 | [A brute-force setting an export's attributes hold as null replaces the stack's value, while the registration names the stack's](0046-null-brute-force-attribute-replaces-stack-value/intent.md) | bug | delivered | 2026-10-30 | 2026-10-30 |
| 0047 | [Five small defects that earlier intents left behind](0047-small-defects-left-by-earlier-intents/intent.md) | bug | delivered | 2026-10-30 | 2026-10-30 |
| 0048 | [Nothing tells a visitor which applications are deployed, nor which account to sign in with](0048-no-list-of-applications-and-accounts/intent.md) | change | delivered | 2026-10-30 | 2026-10-30 |
| 0049 | [The Docker resources the suite's runs leave behind are never reclaimed](0049-docker-resources-never-reclaimed/intent.md) | bug | delivered | 2026-10-30 | 2026-10-30 |
| 0051 | [tests/0049-docker-preflight.sh's docker shim never runs on Linux, so its AC-07 checks prove nothing there](0051-docker-preflight-test-shim-not-executable/intent.md) | bug | delivered | 2026-10-31 | 2026-10-31 |
| 0052 | [tests/0049-docker-preflight.sh checks that the preflight reaped, never that it reaped before the tests](0052-docker-preflight-test-before-not-compared/intent.md) | bug | accepted | 2026-10-31 | 2026-10-31 |
