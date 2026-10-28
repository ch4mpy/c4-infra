# Spec: The migration guide offers a GitLab CI job the demo host doesn't serve

- Intent: [0032](intent.md)
- Status: approved
- Version: 1
- Risk: standard (no risk rule applies: documentation only; `demo/c4-app`, the workflows and how a secret reaches the host are unchanged, and what the documents tell a GitHub project about its secrets stays, RQ-05; it would be high if a decision changed what `c4-app pull` accepts or where a deployment's secrets live)
- Policies applied: none yet; standing constraints: the product owner's decision of 2026-10-28 (the demo host deploys GitHub projects only; the documents say "not this stack", nothing of the other target), what 0028 fixed for every project, 0029 (an application's tests run the stack's Keycloak from any CI), CLAUDE.md "Verification"
- Approved: 2026-10-28, Jérôme Wacongne (product owner; in the drafting session; every point of attention decided)

## Summary

The README, the migration guide and the demo setup say that the demo host deploys GitHub projects, each from its own GitHub Actions workflow, and that a GitLab project (immo) isn't deployed by this stack, without a word on where it goes. The guide loses what 0028 added for another CI platform and its other GitLab mentions; what that addition said that also holds for a GitHub project stays, and what 0028 fixed for every project stays (PA-01, PA-02). A guard may keep GitLab out of the demo host's documents (PA-03).

## Requirements

- **RQ-01:** `README.md` ("Demo host") and `docs/migration.md` (at the start of "On the demo host") state that the demo host deploys GitHub projects, each from its own GitHub Actions workflow, and that a GitLab project isn't deployed by this stack (the guide's "In dev" applies to it, not its demo steps); neither names nor describes another target. (intent: outcome; the decision of 2026-10-28)
- **RQ-02:** `docs/demo-setup.md` step 9 adds a GitHub project: its secrets go in its repository's `demo` environment, with no other platform's secret variables. (intent: outcome; Demo operator)
- **RQ-03:** No step of the three documents offers to deploy a GitLab project, or a project built on another CI platform, onto the demo host: no job for another platform, no GitLab registry among a project's registries, no GitLab project in a demo step's examples. (intent: outcome, "no step suggests…"; problem)
- **RQ-04:** The registries demo step 3 names for a project's own images follow PA-01; wherever the guide sends a project to `pull --registry`, the forms `--registry` and `--registry-user` accept are given (step 3 points to them today). (intent: outcome, "what 0028 fixed for every project stays")
- **RQ-05:** Each rule the other-platform paragraph states that also holds for a GitHub project stays stated in demo step 3 or 5 (PA-02): the registry's token from a secret, on stdin, never on a command line; `pull` without `--registry` logs in nowhere, enough when every image is public; the deployment's secrets given to its `demo` environment only, never printed. (intent: outcome, "what 0028 fixed… stays")
- **RQ-06:** Per PA-03: a test of the suite fails when a document outside `docs/intent/` names GitLab other than in RQ-01's statement, or when that statement is missing from `README.md` or `docs/migration.md`. (intent: outcome)
- **IV-01:** The GitHub example of demo step 5 stays byte for byte: `tests/0002-workflow.sh` and `tests/0002-accounts.stand-in.sh` (AC-08) read its lines. (intent: constraint)
- **IV-02:** What 0028 fixed for every project stays: the containers keep their demo ports (dev step 1, `tests/0004-registry.sh` docs), a public image runs with no login, the token on stdin, the host's dated status. (intent: outcome)
- **IV-03:** A GitLab project keeps the dev stack: "In dev", its registry entry, and README "Keycloak in an application's tests" (a CI that can't read c4-infra reads the image, 0029) are unchanged. (intent: the decision concerns the demo host only)
- **IV-04:** `demo/c4-app`, `.github/workflows/` and `registry.txt` are unchanged. (intent: affected systems, docs only)

## Out of scope

- Where and how a GitLab project is deployed (a Kubernetes cluster at Scaleway, its pipeline still to define): the documents name none of it.
- `c4-app pull --registry` and its forms (code, unchanged under every PA-01 option); 0028's pre-existing finding, `--registry-user` refusing a GitLab deploy token's user (`gitlab+deploy-token-<id>`, `demo/c4-app:450`): no project deploying there needs it, no bug intent.
- immo's registry entry (`registry.txt:24`): its `demo-host` column is mandatory (`registry.sh:173`, `:205-207`), `immo.c4-soft.com` stays reserved and unused; making it optional is code, a new intent if wanted.
- `docs/intent/` (0028's plan, 0029's spec: "on GitLab as on GitHub" for the tests): records, never rewritten.

## Design

### Current behaviour

At `main` 62ef9b2 (lines moved since the intent's `:163`: 0026, 0027 and 0029 merged after it).

- `docs/migration.md:166-171` (demo step 3): a project's own image comes from "its registry (GHCR, GitLab's, any registry `sudo c4-app pull --registry` logs in to)"; an image behind a login comes through `pull --registry … (step 5 below, which gives the forms it accepts)`, one registry per pull.
- `docs/migration.md:222-227` (step 5's lead-in): host key pinned, every action pinned, "its registry's token on stdin: GHCR's here"; `:229-271` the GitHub example (`environment: demo`, `:232`; the token on stdin, never on a command line, `:261`, `:265`).
- `docs/migration.md:273-283`: "On another platform (GitLab, any CI that runs a shell)…": the same job's order, the token from a platform's secret variable on stdin, the forms (`:279-280`: a host with an optional `:port`, no path; a user of letters, digits, `.`, `_`, `-`), `pull` without `--registry` logs in nowhere (`:280-281`), the `VPS_*` values as that platform's secrets, scoped to the protected branch or environment, never printed (`:281-283`). The forms, the no-login `pull` and "never printed" are stated nowhere else.
- `docs/migration.md:302` (demo step 7, backups): "immo: `rest_api_db` `postgres`, `rustfs` `volumes`" (0027), a GitLab project's demo labels.
- `docs/demo-setup.md:231-232` (step 9.5): "on another platform than GitHub, the same three values as its CI's secret variables".
- `README.md` names no CI platform: "Demo host" (`:597-605`) and "What an application's deployment does" (`:700-702`) say "its own workflow"; nothing says which projects the demo host deploys. `:473-493` (0029) addresses "a compose file of its CI" and "a CI that can't read c4-infra": an application's tests, not its deployment.
- `git grep -n -i gitlab -- ':!docs/intent/'`: `docs/migration.md:167` and `:273` only; nothing names Kubernetes or Scaleway.
- `demo/c4-app` `cmd_pull` (`:429-460`): without `--registry`, `compose pull` with no login; with it, `docker login <host> -u <user> --password-stdin` in a temporary configuration, the host `^[A-Za-z0-9.-]+(:[0-9]+)?$`, the user `^[A-Za-z0-9._-]+$` (`:449-450`): any registry, GHCR, Docker Hub or a private one. The stand-in proves no login (`tests/0002-accounts.stand-in.sh:188` runs the document's pull without `--registry`; `:295` a refused one).
- Tests reading these documents: `0002-workflow` and `0002-accounts.stand-in` (the GitHub example), `0004-registry` (dev section, registry columns), `0027-docs` (backup terms in each document), `0029-description` (the guide's link to the tests' section), `0016-no-real-provider` (all of `docs/`), `0008-certificate-scripts` and `0009-master-realm.stand-in` (`demo-setup.md`). A change of a `.sh` redeploys the unchanged stack at the merge (`deploy-demo.yml:9-11` ignores only Markdown and `.claude/`).

### Behaviour per persona

- **Application, on GitHub** (Turu, Hurura'a, Tickee, Faito): the same steps; step 5 shows the GitHub job only; the registry rules it relied on stay (RQ-04, RQ-05, IV-02).
- **Application, on GitLab** (immo): follows "In dev" and the tests' Keycloak as before; at "On the demo host", reads that this stack doesn't deploy it, and nothing of where it goes; no demo step names it.
- **Demo operator**: step 9 adds GitHub projects, their secrets in their repository's `demo` environment; the README's statement answers a request for a GitLab project.

### API and contracts

None changed: `sudo c4-app pull [--registry <host> --registry-user <user>]` (`README.md:631`, `demo/c4-app:112`) as today.

### User interface

The statement of RQ-01, as proposed: "The demo host deploys GitHub projects, each from its own GitHub Actions workflow. A GitLab project (immo) isn't deployed by this stack: "In dev" applies to it, not these steps."

### Data

None.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| The decision of 2026-10-28: GitHub projects only, "not this stack" | RQ-01 to RQ-03; Out of scope: no other target named |
| 0028: ports, public images, the token on stdin, status | IV-01, IV-02, RQ-05 |
| 0029: an application's tests from any CI | IV-03 |
| CLAUDE.md "Verification": the tests reading the documents | AC-07; a new test declares its `covers:` (RQ-06) |

## Points of attention

### PA-01: The registries the guide names for a project's own images

- Issue: step 3 names "GHCR, GitLab's, any registry `sudo c4-app pull --registry` logs in to". `c4-app` logs in to any registry, and a GitHub project may push to Docker Hub or a private one; the demo host's projects use GHCR today, and nothing here proves a login to any registry.
- Options: A "GHCR, or any registry `sudo c4-app pull --registry` logs in to", with the forms it accepts / B GHCR only: the guide gives `--registry ghcr.io` alone, `--registry`'s other hosts staying in README "Accounts" (`:631`) and `c4-app`'s usage.
- Recommendation: A: the guide states `c4-app`'s contract as the code has it, minus GitLab; B would tell a GitHub project on Docker Hub less than the host accepts, for no gain.
- Decides: PO
- Decision: A, as recommended — Jérôme Wacongne (product owner), 2026-10-28

### PA-02: The other-platform paragraph

- Issue: `docs/migration.md:273-283` is GitLab's job, but three of its rules hold for every project and are stated nowhere else: the forms, `pull` without `--registry`, secrets never printed.
- Options: A remove it; step 3 takes the forms and the no-login `pull` (one clause each), step 5's lead-in "never printed" for the `demo` environment's secrets / B replace it, after the example, with a GitHub-only paragraph: another registry than GHCR (its host, its user, its token a secret of the `demo` environment, on stdin), the forms, `pull` without `--registry` when every image is public, the secrets never printed / C keep it, "GitLab" removed (rejected: no other platform deploys there).
- Recommendation: A: each rule once, where it applies (registries in step 3, the job in step 5); B repeats step 3 after the example.
- Decides: PO
- Decision: A, as recommended — Jérôme Wacongne (product owner), 2026-10-28

### PA-03: A guard against GitLab on the demo host

- Issue: 0028 added the paragraph hours before the decision, and 0029's text addresses CI on any platform: a later change may offer it again. A test costs a few lines and seconds, and its merge redeploys the unchanged stack (not Markdown).
- Options: A no test: the plan's proof greps once / B a test of the suite (RQ-06), built like `tests/0016-no-real-provider.sh`: outside `docs/intent/`, "GitLab" only in RQ-01's statement, which `README.md` and `docs/migration.md` hold; it fails on `main` today (`:167`, `:273`).
- Recommendation: B: the decision is recent and easily undone by an agent writing CI guidance; the intent that documents a GitLab target, if ever here, changes the guard knowingly.
- Decides: PO
- Decision: B, as recommended — Jérôme Wacongne (product owner), 2026-10-28

## Acceptance criteria

- **AC-01:** Given `README.md` "Demo host" and `docs/migration.md` "On the demo host", then each opens with RQ-01's statement, and `grep -n -i -E 'kubernetes|scaleway|k8s' README.md docs/*.md` prints nothing. (RQ-01)
- **AC-02:** Given `docs/demo-setup.md` step 9, then it adds a GitHub project, its secrets in its repository's `demo` environment, and names no other platform. (RQ-02)
- **AC-03:** Given `README.md` and `docs/*.md`, when `grep -n -i -E 'gitlab|another platform|other platform|any CI|immo'` runs, then it prints RQ-01's statement only. (RQ-03)
- **AC-04:** Given demo step 3, then it names the registries of PA-01 (A: GHCR and any registry `pull --registry` logs in to, with the forms), each form matching `demo/c4-app:449-450`. (RQ-04)
- **AC-05:** Given demo steps 3 and 5, then each rule of RQ-05 is found there, read against `cmd_pull` (`demo/c4-app:429-460`). (RQ-05)
- **AC-06:** Given PA-03 B, when the guard runs on `main` before the change, then it fails naming `docs/migration.md:167` and `:273`; after it, it passes; a line naming GitLab added to `README.md`, or RQ-01's statement removed, makes it fail. (RQ-06)
- **AC-07:** Given the change, when `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --changed --all` runs, then `verification passed`, `0002-workflow`, `0004-registry`, `0016-no-real-provider`, `0027-docs`, `0029-description`, `0008-certificate-scripts`, `0002-accounts.stand-in` and `0009-master-realm.stand-in` among its tests; `git diff main -- demo/ .github/ registry.txt` is empty; the example's lines and README "Keycloak in an application's tests" are unchanged. (IV-01 to IV-04)

## Intent questions

- None open: settled on 2026-10-28 (the documents say "not this stack", nothing of the other target), applied by RQ-01. Whether `--registry` stays useful to a GitHub project: yes, `c4-app` logs in to any registry (`demo/c4-app:449-453`) → PA-01.

## Change log

- v1 — 2026-10-28 — first version, at the product owner's request (the intent said "Spec needed: no"; this spec's commit sets it to "yes")
- v1 — 2026-10-28 — approved by the product owner in the drafting session: PA-01 A, PA-02 A, PA-03 B, as recommended.
