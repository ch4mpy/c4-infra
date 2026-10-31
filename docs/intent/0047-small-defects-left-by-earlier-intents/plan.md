# Plan: 0047, 0048 and 0049, one pass, one delivery

- Specs: [0047 v1](spec.md) (approved 2026-10-30, PA-01 B), [0048 v2](../0048-no-list-of-applications-and-accounts/spec.md) (v1 approved 2026-10-30, PA-01 B, PA-02 A, PA-03 A; v2 approved with this plan, the section below), [0049 v1](../0049-docker-resources-never-reclaimed/spec.md) (approved 2026-10-30, PA-01 B, PA-02 A, PA-03 A, PA-04 A)
- Status: approved
- Branch: `0047-small-defects-left-by-earlier-intents`, carrying the three intents (worktree `D:/workspaces/c4-infra-0047`)
- Approved: 2026-10-30, Jérôme Wacongne (engineer, product owner and tech lead: the plan mode's approval, the tech lead's for 0047 and 0048, both high risk)

## Context

The product owner's batch of 2026-10-30, done as 0040 to 0046 were: each intent documented and specified, then one pass for everything specified, one review round, one full run, one delivery.

- **0047**: five defects the triage of the handover kept: the demo setup guide creates the `demo` environment without the branch restriction it promises; `new-realm-ids.sh` lists the users' new ids for Keycloak's layout only; the hostile build fixtures give their pre-0011 reasons; `stand_in_https`'s wait has no time bound; `other_features` passes on nothing.
- **0048**: a landing page at the infra host's root, dev and demo, listing each registered application and its accounts; on the demo host no password on the page: the registration draws them, keeps them, sets them in Keycloak, and `sudo c4-app accounts` hands them to the application's workflow, which comments them on the deployed pull request.
- **0049**: the twin of the skills' 0122 (their plan's step 0 waits for it on `main`): a library `tests/lib/docker-preflight.sh` (labels, reaper, preflight) called by `tests/run.sh` at its lock take, c4-infra's tests labelling what they create and removing it with `rm -f -v`, the stand-in volumes labelled `keep=<clone>`.

## 0048 spec v2 (step 0, the product owner's request of 2026-10-30)

"Chaque section d'application contient une sous-section users (`<username> [<group>]`) et une sous-section groups (`<group> [<roles>]`); la page décrit un état au déploiement et ne suit pas les modifications faites dans Keycloak au runtime." v2 changes, approved with this plan:

- **RQ-01**: an accounts file line is `<realm> <username> <dev password | ->`: no label; the groups and roles come from Keycloak.
- **RQ-03**: each application's section: its name, a link; a `users` subsection, one line per declared account, `<username> [<group>, …]` (in dev `<username> <dev password> [<group>, …]`); a `groups` subsection, one line per group of those users, `<group> [<role>, …]`: the group's own realm roles, then its client roles as `<client>:<role>`, each list sorted; a group is shown as `<realm>/<group path>` when the application's accounts span several realms, else by its path. The simulated providers (PA-03 A): a `users` subsection only.
- **New RQ-12**: the users' groups and the groups' roles are read from Keycloak by the registration that gives `--accounts`, after its realms are imported and, on the demo host, its passwords set; kept until the next such registration; the page describes that registration's state and doesn't follow later changes in Keycloak.
- **RQ-04**: the escaping covers the values read from Keycloak (group, role and client names), which RQ-02 doesn't filter.
- **RQ-09**: `sudo c4-app accounts` prints `<realm> <username> <password>`.
- **AC-01, AC-02** rewritten for both subsections; **AC-06**: a group whose name holds `&` and `<` in the fixture realm reaches the page escaped; **new AC-10**: a user added to a group after the registration leaves the page unchanged until the next registration.

## Design

### 0047

- `docs/demo-setup.md:125`, `:245`: `gh api -X PUT repos/$R/environments/demo -F 'deployment_branch_policy[protected_branches]=false' -F 'deployment_branch_policy[custom_branch_policies]=true'`, then `gh api -X POST repos/$R/environments/demo/deployment-branch-policies -f name=main` (`$A`: the application's branch), and the read-back `gh api repos/$R/environments/demo --jq .deployment_branch_policy` plus `…/deployment-branch-policies --jq '[.branch_policies[].name]'`. PA-01 B: the stack's two commands run against `ch4mpy/c4-infra` (GET before and after identical; the POST answers 303); the `-F` nested form checked by that run.
- `new-realm-ids.sh`: the users read with `jq -r '.users[]? | [.id, .username] | @tsv' < "$file"` (CR stripped, CLAUDE.md), before the replacement; a file `jq` can't read: named, left, `refused=1`. `tests/0017-new-realm-ids.sh`: the same fixture reformatted by `jq .` (both users printed, their new ids the file's), and a non-JSON file (exit 1, named, unchanged).
- `tests/fixtures/0007/hostile/build-*.yml`: headers say what each holds and that `sudo c4-app up` refuses it because it builds (intent 0011), before any container starts.
- `tests/lib/stand-in-host.sh` `stand_in_https`: each wait attempt `--max-time 5`, retried on 7, 35 and 28 until a 30 s deadline (`date +%s`, POSIX sh in the stand-in); a wait that ends on 28 returns it without the final request; the final request as today. `tests/0035-https.stand-in.sh`: with the stack up, the proxy stopped and a listener that accepts and never answers on the stand-in's 443 (perl's `IO::Socket::INET`, in `ubuntu:24.04`'s `perl-base`), `stand_in_https` returns non-zero within 40 s; the listener killed, the proxy started again (if reading the root needs the proxy running, the listener goes on another address and the check calls the wait through `--connect-to` of its own: decided at the step, recorded).
- `tests/0029-image-facts.sh` `other_features [<file>]`: first `jq -e '.features | type == "array" and length > 0' < "$file"`, else "no feature read from <file>", return 1; a new check that it fails on an empty file.

### 0048

- **Accounts file and checks** (`register-app.sh`): `--accounts <file>` parsed with the others; RQ-02's checks with the realm and theme checks (before any change), the realm among `REG_REALMS`; refusals in the existing "nothing was registered" block. `--account-passwords-env <VAR>` (demo, from `c4-app`): `<realm> <username> <password>` lines in that variable, as `--rabbitmq-password-env` does.
- **After the realms' import** (only with `--accounts`): on the demo host, for each account, its id (`account get users -r <realm> -q username=<u> -q exact=true --fields id`), then its password by `account -i update users/<id>/reset-password -r <realm> -f - < <json on stdin>` (the 0006 test's form, never a command line); no user or a refusal (read-only LDAP): stop, naming the account and Keycloak's answer (RQ-08). Then the snapshot: each user's groups (`users/<id>/groups`), each group's mappings (`groups/<gid>/role-mappings`), into `caddy/apps/<app>.accounts` (users, dev passwords in dev only, groups and roles; readable by c4-infra, `own`), never a drawn password.
- **The page** (`write_index`): both environments; reads `caddy/apps/*.caddy` and each `<app>.accounts`, the registry's dev or demo host, the simulated realms' users from `keycloak-import/simulated-*-realm.json` (`jq`, passwords in dev only); every value through one `html_escape`; a `meta` robots `noindex`; inline style. Called at the end of every registration (today only when the site changed, `:634`) and by `--index-only`.
- **Serving** (`caddy/Caddyfile`): `handle /` moves from `env/dev.caddy` into the infra host's block, before the final `handle`, with `Content-Security-Policy "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"` and `X-Robots-Tag "noindex"`.
- **`demo/c4-app`**: `register --accounts <file>` (`staged_path`) and `--new-passwords`; the store `/var/lib/c4-apps/.<app>.passwords` (0600 root:root, outside `copy_in`'s wipe), written before `register-app.sh` runs: the accounts file's realm and username pairs, a password drawn (24 characters, `/dev/urandom`, base64url, redrawn until it holds lowercase, uppercase, digit and `-` or `_`) for a pair it lacks, or for all with `--new-passwords`, pairs no longer declared dropped; handed to `register-app.sh` in `C4_APP_ACCOUNT_PASSWORDS`. `accounts` subcommand: the store's lines; usage and header.
- **`demo/deploy.sh`**: `bash ./register-app.sh --index-only` after the Caddy reload (as c4-infra: the page's data is c4-infra's). `up.sh:85` unchanged.
- **Docs**: README (the landing page row `:153`, "What an application provides", "Demo host" intro, "Accounts" list, "What an application's deployment does"); `docs/migration.md` step 5: the accounts file, `--accounts` on the register line, the workflow's step (`out=$(ssh … sudo c4-app accounts)`, `::add-mask::` per password, the merged pull request from `gh api repos/$GITHUB_REPOSITORY/commits/$GITHUB_SHA/pulls`, `gh pr comment`, else `$GITHUB_STEP_SUMMARY`; `permissions: pull-requests: write`), no new `uses:` (0002-workflow pins them).
- **Fixtures**: Faito's `tests/fixtures/0002/faito` realm gets two users in two groups with realm and client roles, one group named with `&` and `<`, and an accounts file, so that the migration guide's register line, which `tests/0002-accounts.stand-in.sh` runs, can carry `--accounts`.

### 0049

- **`tests/lib/docker-preflight.sh`** (new; bash, coreutils, `awk`, `sed`, docker CLI; sources nothing, no `jq`): on source, `C4_INFRA_RUN` set and exported when unset (`<epoch>-<pid>-<random>`), `C4_DOCKER_LABEL_NS` defaulting to `c4-infra`. `docker_labels()`, `docker_keep_labels()`, `docker_reap()`, `docker_preflight()` defined at column 0 (the skills' step-0 check counts `^docker_(labels|reap|preflight)\(\)`: 3). `docker_labels <owner> [ttl]` prints `--label` and `<ns>.owner|run|created|ttl=…` one per line, plus `<ns>.lock=$C4_DOCKER_LOCK` when set (PA-01 B); callers `mapfile -t C4_LABELS < <(docker_labels c4-infra)`. Reaping: containers (`rm -f -v`), networks, volumes, images labelled `<ns>.run`, over when `created + ttl < now`, or when their `<ns>.lock` is `$C4_DOCKER_LOCK` and their run isn't `$C4_INFRA_RUN` (the reaper runs only as the lock's holder); kept resources whose `<ns>.keep` path is gone and that no container uses; then, unless `C4_DOCKER_REAP=labelled`: `docker buildx prune -f --max-used-space <C4_DOCKER_BUILD_CACHE_GB>`, `docker volume ls -q -f dangling=true -f label=com.docker.volume.anonymous` removed, and the untagged images of the `--pins` file's repositories that no container uses. Measures: one labelled `alpine:3 --rm` (`df -Pk /`, `/proc/meminfo` `MemAvailable`), the host's `df -Pk "$C4_DOCKER_DISK_DIR"` (default Linux `~/.docker/desktop/vms/0/data`, Windows `$(cygpath -u "$LOCALAPPDATA")/Docker/wsl/disk`; none: one line saying it isn't measured), the host's `/proc/meminfo` `MemAvailable` or `MemFree`, plus `SwapFree`; floors and messages as the spec's *API and contracts*; every line `docker preflight: …`; nothing restarts, resets or compacts Docker.
- **Never labelled with a run**: the suite lock and its queue tickets (`tests/lib/suite-lock.sh`), which keep their `c4-infra.suite.*` labels only, so that the holder's reaper can't take a waiting run's ticket (IV-01); their `docker rm -f` gets `-v`.
- **`tests/run.sh`**: sources the library next to the lock's; after `suite_lock_take` (`:375`), before `run_start`: `export C4_DOCKER_LOCK=$SUITE_LOCK_NAME`, a `docker preflight: run $C4_INFRA_RUN` line, then, unless `C4_DOCKER_PREFLIGHT=off`, `docker_preflight --pins <(bash tests/docker-pins.sh) || exit 1`; `remove_stand_in_hosts` with `-v`; header.
- **`tests/docker-pins.sh`** (new, under `tests/`: no covers rule; covered by the 0049 tests): the images of `compose.yml` and its overrides, `keycloak-image.properties`'s, the tests' (`caddy:2.11.4-alpine`, `alpine:3`, `bash:5.2`, `postgres:18.6`, `grafana/otel-lgtm`, `ubuntu:24.04`) and the built ones (`c4-infra/keycloak`, `c4-infra/reverse-proxy`, `c4-infra/stand-in-host`, `c4-test/probe`), one per line.
- **`tests/lib/stand-in-host.sh`**: `stand_in_up` creates `$STAND_IN_VOLUME` with `docker_keep_labels c4-infra <clone>` (`<clone>`: the parent of `git -C "$STAND_IN_ROOT" rev-parse --path-format=absolute --git-common-dir`); an existing one without `<ns>.keep` removed first, once (PA-03 A; its images pulled again); the stand-in container with the run labels; the two images built with `docker_keep_labels`; `rm -f -v`.
- **The tests' host creators** (the exploration's inventory: 18 `run --rm` lines, 27 `run -d` lines, 1 `create`, 6 `network create`, 2 `volume create`, 2 `build -t …:before*`, the compose projects of 0011, 0012, 0026 through `labels:` that compose fills from `C4_INFRA_RUN`): each sources the library and passes `"${C4_LABELS[@]}"`; every `docker rm -f` and plain `docker rm` on the host gets `-v`; `tests/0013-upgrade.stand-in.sh` and `tests/0016-simulated.stand-in.sh` remove their `before` tags in their EXIT trap. What runs inside a stand-in is untouched. `networks.sh`'s application networks stay the dev stack's (their tests remove them, as today).
- **The tests that copy `run.sh`**: `tests/0017-run.sh` and `tests/0022-lanes.sh` export `C4_DOCKER_PREFLIGHT=off` beside their lock name; `tests/0037-queue.sh` doesn't copy it (unchanged).
- **Docs**: CLAUDE.md "Verification" (the preflight's lines, `C4_DOCKER_PREFLIGHT=off`, the floors' variables); `tests/lib/docker-preflight.sh`'s header (the contract the skills read). c4-infra has no evals: none run.

## Files

| File | Change | For |
| --- | --- | --- |
| `docs/demo-setup.md` | the two environments' commands, the read-back | 0047 RQ-01, AC-01 |
| `new-realm-ids.sh`, `tests/0017-new-realm-ids.sh` | users read with `jq`; jq-layout and non-JSON cases | 0047 RQ-02, AC-02 |
| `tests/fixtures/0007/hostile/build-*.yml` (7) | headers | 0047 RQ-03, AC-03 |
| `tests/lib/stand-in-host.sh`, `tests/0035-https.stand-in.sh` | `stand_in_https`'s bounded wait, its stall check; (0049) the volume's and images' labels | 0047 RQ-04, AC-04; 0049 RQ-01, RQ-07 |
| `tests/0029-image-facts.sh` | `other_features` and its empty-file check; (0049) labels, `-v` | 0047 RQ-05, AC-05; 0049 RQ-01, RQ-02 |
| `register-app.sh` | `--accounts`, `--account-passwords-env`, checks, passwords set, snapshot, `write_index` both environments and escaped, called at every registration; header | 0048 RQ-01 to RQ-04, RQ-06 to RQ-08, RQ-10, RQ-12 |
| `caddy/Caddyfile`, `caddy/env/dev.caddy` | `handle /` with its headers in the shared block | 0048 RQ-05 |
| `demo/c4-app` | `register --accounts`, `--new-passwords`, the store, `accounts`; usage, header | 0048 RQ-07, RQ-09 |
| `demo/deploy.sh` | `--index-only` after the reload | 0048 RQ-06 |
| `tests/fixtures/0002/faito/*`, `tests/fixtures/0048/` (new: a dev realm with users and groups, its registry, accounts files) | users, groups, roles, accounts | 0048 AC-01 to AC-10 |
| `tests/0004-registry.sh`, `tests/0003-dev-routes.sh`, `tests/0003-demo-edge.sh`, `tests/0002-accounts.stand-in.sh` | refusals and escaping (stubs, `--index-only`); the dev page; the demo root `200` and its headers (its own `html` mounted); the guide's register line with `--accounts` | 0048 AC-01 to AC-04, AC-06 |
| `tests/0048-landing-page.sh` (new, dev stack: `tests/0013-delegation.sh`'s fixture-registry pattern), `tests/0048-accounts.stand-in.sh` (new) | AC-01, AC-06, AC-10 in dev; AC-02, AC-05, AC-07, AC-08 on a stand-in | 0048 |
| `README.md`, `docs/migration.md` | the page, the accounts, the workflow step | 0048 RQ-11, AC-09 |
| `tests/lib/docker-preflight.sh` (new), `tests/docker-pins.sh` (new), `tests/run.sh`, `tests/lib/suite-lock.sh` | the library, the pins, the preflight at the lock take, `-v` | 0049 RQ-03 to RQ-12, IV-01, IV-02 |
| the tests that create on the host's Docker (about 25, listed by the exploration), `tests/0017-run.sh`, `tests/0022-lanes.sh` | labels, `-v`, `before` tags removed; `C4_DOCKER_PREFLIGHT=off` | 0049 RQ-01, RQ-02, RQ-11 |
| `tests/0049-docker-labels.sh`, `tests/0049-docker-preflight.sh`, `tests/0049-docker-reap.stand-in.sh` (new) | static check; kill -9, floors, no cleaning during tests on the host's Docker in a namespace of their own; the unlabelled classes and `keep` inside a stand-in | 0049 AC-01 to AC-09 |
| `CLAUDE.md` | "Verification": the preflight | 0049 RQ-06, RQ-09 |
| `docs/intent/0047…/plan.md` (this plan), `0048…/plan.md` and `0049…/plan.md` (pointers), `0048…/spec.md` (v2), the three `intent.md`, `docs/intent/README.md`, `docs/intent/HANDOVER.md` | | |

## Order of work

Bootstrap mode, one pass (the product owner's), on the batch branch in its worktree; 0017-export-realm, the stand-in tests and the full run from the main checkout detached at the commit. Before any run: no other session's `tests/run.sh` (PowerShell `Get-CimInstance`). `TMPDIR=~/.cache/c4-infra-tests` always.

0. **Spec 0048 v2 and the plan** — skill: none — check: `git status --short` empty. `spec: 0048 v2 …` (the section above), this plan into 0047's `plan.md`, pointers into 0048's and 0049's, the three intents `planned`, the index rows; `plan: …`; push.
1. **0047, failing tests** — check: `tests/0017-new-realm-ids.sh` KO on the jq layout and the non-JSON file; `tests/0029-image-facts.sh` KO on the empty file only; `tests/0035-https.stand-in.sh`'s stall check KO (under `timeout 60`, "did not return"); the KO lines under *Deviations*. Commit `test(0047): …`.
2. **0047, the fixes** — check: the three tests `every check passed`; PA-01 B: GET of c4-infra's `demo` environment and branch policies, the guide's two commands, GET again: identical, recorded. Commit `fix(0047): …`.
3. **0049, failing tests** — check: `tests/0049-docker-labels.sh` KO naming each unlabelled creator and each `rm` without `-v`; `tests/0049-docker-preflight.sh` KO (no library). Commit `test(0049): …`.
4. **0049, library, pins, `run.sh`, lock, stand-in** — check: `bash -n`; `tests/0049-docker-preflight.sh` green; `docker_preflight --no-clean --pins <(bash tests/docker-pins.sh)`, sourced in a shell, prints this workstation's measures (the first real run, step 5's, prunes about 9 GB of build cache: expected, recorded). Commit `fix(0049): …`.
5. **0049, the tests' creators** — check: `tests/0049-docker-labels.sh` green; `bash tests/run.sh --changed HEAD~1` (stand-in aside) green. Commit `fix(0049): …`.
6. **0048, registration and page in dev** (`register-app.sh`, Caddy, fixtures, 0004, 0003-dev-routes, 0003-demo-edge, 0048-landing-page) — check: those tests green. Commit `feat(0048): …`.
7. **0048, the demo host** (`c4-app`, `deploy.sh`, Faito's fixture, 0002-accounts, 0048-accounts.stand-in) — check: both stand-in tests green. Commit `feat(0048): …`.
8. **Docs** (README, migration guide, CLAUDE.md, the library's header) — check: read; `tests/0002-workflow.sh` green. Commit `docs(0047, 0048, 0049): …`.
9. **Review** — one round, a fresh agent per intent on its own commits: bugs and security (0047 and 0048 high, the security pass on what the demo host runs as root and on the page's origin); fixes, *Deviations*.
10. **Verification** — `bash tests/run.sh --all` from the main checkout detached at HEAD (every test: `tests/lib/` changed; one stand-in lane), `verification passed`; 0049 AC-01: the run's id from its `docker preflight: run` line, then `docker ps -a`, `network ls`, `volume ls`, `images` filtered by `label=c4-infra.run=<id>` empty, no `c4-infra/keycloak:before*`; mutations in throwaway worktrees: 0048, `write_index` printing a demo password → `tests/0048-accounts.stand-in.sh` KO; 0049, the lock label ignored by the reaper → AC-03 KO; 0047's KOs are step 1's. Evidence into `## Verification`; `plan: verification of 0047, 0048 and 0049`; push.
11. **Delivery** — the three `delivered`, `git merge --no-ff` into `main` (`merge(0047, 0048, 0049): …`), the index rows checked, HANDOVER (the skills' 0122 v2 to take: the `<ns>.lock` label and the variables' names; Tickee's accounts file and workflow step), push `main`; deploy-demo followed: `https://infra.c4-soft.com/` `200`, its CSP and `X-Robots-Tag`, Tickee's link, the simulated providers' users, no password; Tickee `302`. PA-04 A: the product owner's go asked, then `docker rmi c4-infra/keycloak:0013 c4-infra/keycloak:0012-dev c4-infra/keycloak:26.7` if no container uses them.

## Risks

- The holder's reaper removes a waiting run's ticket or another session's resource → the lock and tickets carry no run label; the lock-label rule only reaps resources of the same lock and another run; tests of the reaper in a namespace of their own with `C4_DOCKER_REAP=labelled`, the unlabelled classes only inside a stand-in.
- The first preflight's prune and the stand-in volume's recreation slow the first full run (rebuilds, pulls) → expected, recorded; floors env-overridable.
- A label left off a creator → `tests/0049-docker-labels.sh` reads them all; its exclusions (inside a stand-in) listed in its header.
- The demo passwords leak (page, logs, registration output) → never written outside the root-only store and `sudo c4-app accounts`; AC-02, AC-07 grep the page and the output; Keycloak's CLI gets them on standard input.
- A group or role name from Keycloak injects HTML on Keycloak's origin → escaped, the page's policy allows no script; AC-06 with a real group name holding `&` and `<` (if Keycloak refuses such a name, the writer's own test proves it: recorded).
- A realm whose password policy forbids reusing a password refuses the password set again → none today (read 2026-10-30); Keycloak's answer named (RQ-08).
- `tests/0002-accounts.stand-in.sh` runs the guide's register line → Faito's fixture gets its users and accounts file in the same step as the line.
- The demo's first deployment writes the page before any application registers with accounts → Tickee's link alone, as RQ-01 says.

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| 0047 AC-01 | reading, command | the guide; PA-01 B's GET before and after |
| 0047 AC-02 to AC-05 | automated tests, mutation | `0017-new-realm-ids`, `0007-compose-check.stand-in` (headers read), `0035-https.stand-in`'s stall check, `0029-image-facts`; KO at step 1 |
| 0048 AC-01, AC-06, AC-10 | automated test (dev stack) | `0048-landing-page` |
| 0048 AC-02, AC-05, AC-07, AC-08 | automated test (stand-in), mutation | `0048-accounts.stand-in`, `0003-demo-edge` (headers) |
| 0048 AC-03, AC-04 | automated test | `0004-registry` (stubs), `0048-landing-page` |
| 0048 AC-09 | reading | README, `docs/migration.md` |
| 0049 AC-01 | command | step 10's label filters after `--all` |
| 0049 AC-02, AC-08 | automated test | `0049-docker-labels` |
| 0049 AC-03, AC-05, AC-07, AC-09 | automated test, mutation | `0049-docker-preflight` (this workstation) |
| 0049 AC-04, AC-06 | automated test | `0049-docker-reap.stand-in` |
| No regression | command | step 10's `--all`, `verification passed` |

## Deviations

- 2026-10-30 — the work split in three worktrees, each merged back into this branch: 0049 by an agent (`D:/workspaces/c4-infra-0049`, branch `0049-docker-preflight`), 0048 (`D:/workspaces/c4-infra-0048`, branch `0048-landing-page`, from da563d1), 0047 here; every test that starts containers run under the suite's lock (`source tests/lib/suite-lock.sh && suite_lock_take && exec bash <test>`), so that no two stand-ins run at once.
- 2026-10-30 — step 1 (da563d1), before the fixes (`~/.cache/c4-infra-tests/0047-before-*.log`): `tests/0017-new-realm-ids.sh` `4 check(s) failed` (the jq layout's two users not printed, the non-JSON file exits 0 and is changed); `tests/0029-image-facts.sh` `1 check(s) failed`, the new one only ("fails when it reads no feature"); `tests/0035-https.stand-in.sh` `2 check(s) failed`: the stall check "did not return within 60 s", and AC-06 "the checkout is unchanged", from my edits of the worktree during that run, not a defect (the run after the fix, the worktree untouched, passes it).
- 2026-10-30 — step 2: the three tests `every check passed` (`0047-after-*.log`; the stall check `ok`). PA-01 B, on `ch4mpy/c4-infra`: settings before and after identical (`deployment_branch_policy` `{"custom_branch_policies":true,"protected_branches":false}`, branch policies `[{"name":"main","type":"branch"}]`); the `PUT` with the `-F 'deployment_branch_policy[…]'` fields exits 0; the `POST` of an existing pattern answers `200` (gh follows the documented 303 to the existing policy), not an error. `other_features` gets its file as a parameter at step 1 (no behaviour change), its `jq` status check at step 2: the code under test lives in the test, as 0038's `form()`.
- 2026-10-30 — 0048, steps 6 and 7 (3e74d24, dd9d5a0, 66e0b4c, b1826dc on `0048-landing-page`, merged as 4f5c3f9): `tests/0004-registry.sh scripts` passes every 0048 check; its three other KOs (`duplicate realm, register-app.sh --app faito`, `unknown app` twice) come from the worktree having no `.env` (`INFRA_ENV` empty), the same in 0047's worktree without the change: they pass from the main checkout. `tests/0048-landing-page.sh` from the main checkout detached at 66e0b4c (the proxy serves that checkout's `caddy/html`), then back on `main`, the proxy reloaded and the page written again: `every check passed`. `tests/0002-accounts.stand-in.sh`, the guide's register line now carrying `--accounts <project>.accounts` (Faito's fixture realm given two users in two groups, and `faito.accounts`): `every check passed`. First runs: `tests/0003-demo-edge.sh` KO, its Caddy not started (Docker can't create `/etc/caddy/html` inside the read-only configuration when the checkout has no `caddy/html`, a fresh worktree): the test makes the mount point (gitignored); `tests/0048-accounts.stand-in.sh` KO on the password grants: Keycloak 26.8.1 answers a wrong password `400` `invalid_grant` (measured on `simulated-google`: `{"error":"invalid_grant","error_description":"Invalid user credentials"} http=400`), not the `401` the test expected, and its message's second request, within a second of the first failure, set off the quick-login lockout (60 s), failing the next grants: the test expects `400 invalid_grant` and makes one request a check. Then both `every check passed` (`0048-demo-edge-2.log`, `0048-accounts-2.log`).

## Verification
