# Plan: The demo host builds images the applications' CI already builds, and some stack scripts misreport errors

- Spec: [v2](spec.md)
- Status: approved
- Branch: 0011-demo-builds-and-script-errors
- Approved: 2026-10-23, Jérôme Wacongne (engineer, and tech lead for the high risk; also the product owner)
- Builds on: **0012** and **0013**, implemented first by the product owner's order (2026-10-23): both touch `up.sh`, `registry.sh`, `routes.sh`, `tests/lib/stand-in-host.sh` and the stand-in tests. Step 0 merges them (their branches, then `main` once they are merged); line numbers of the spec's *Current behaviour* will have moved, so this plan names functions, not lines.

## Starting point

- `demo/c4-app`: the `CHECKS` jq program (`build_allowed`, `remote`, the `$v.build` block, `reserved` + `$host`), `check_model` (reads `INFRA_HOST` through `dotenv_value`), and the `up` / `down` / `pull` branches: `down` runs `stage`, `read_model`, `check_model`, then `compose down`. Only `tests/0007-compose-check.stand-in.sh` exercises the build refusals (seven `tests/fixtures/0007/hostile/build-*.yml`); no application fixture builds (the probe image of `0007-isolation.stand-in.sh` is built by the test in the stand-in's daemon, not by `c4-app`).
- `up.sh` `docker exec … caddy reload` failure → always "refuses its configuration"; `tests/0003-up-reload.sh` covers that case with a docker stub that fails the reload. The proxy's own healthcheck (`compose.yml`, `reverse-proxy`) probes the admin API with `wget -q -O /dev/null http://127.0.0.1:2019/config/`: the signal to reuse.
- `networks.sh` `compose_file`: the daemon-less early return writes before the lock; `tests/0007-dev.sh` (`part_rewrite`) already holds the lock from a `bash:5.2` container with `flock` (Git Bash has none) and a docker stub: the model for AC-06.
- `registry.sh` `dotenv_value` and its tests (`tests/0002-register-scope.sh`); `routes.sh` option loop and `tests/0003-routes.sh`'s `refused <fixture> <line> <text>` helper (exit 1, `<file>:<line>:`, message, no site printed).
- Docker Compose v5.6.1 here; the stand-in host runs the demo's.
- Not reproduced (spec, PA-02): defect 5. RQ-08 is a guard, so its test passes before and after.

## Files

| File | Change | For |
| --- | --- | --- |
| `docs/intent/0011-…/spec.md` | modified, step 1: v2 — RQ-01 and AC-01 cover `up` and `pull` only; `down` reads no file (RQ-04); Design and API lines follow; change log | RQ-01, RQ-04, AC-01 |
| `demo/c4-app` | modified: `build` moves from `svc_allowed` to `svc_refused` with one rule `service <s>: build: the demo host runs the images the application's CI pushes to a registry (README.md, "Accounts")`; `build_allowed`, `remote`, the `$v.build` block (sub-keys, contexts, Dockerfile, image, `-` in the name) go; `reserved` no longer adds `$host` and `check_model` no longer reads `INFRA_HOST` nor passes `--arg host`; `down` takes the lock, then `docker compose -p "$app" down --remove-orphans` with no file and no `stage`/`read_model`/`check_model`; header comment updated | RQ-01, RQ-02, RQ-04, RQ-09 |
| `up.sh` | modified: after a failed reload, probe the admin API as the healthcheck does — answers → "refuses its configuration" (Caddy's message, then "fix caddy/…"), does not answer or `docker exec` fails → "the reverse proxy isn't reachable, retry"; `certificate_before` reads a missing `certs/tls.crt` as "none" instead of exiting under `set -e -o pipefail` | RQ-05, RQ-10 |
| `networks.sh` | modified: `compose_file` takes the lock first, then both paths (the daemon-less `services: {}` creation included) write a temporary file renamed into place; header comment | RQ-06 |
| `registry.sh` | modified: `dotenv_value` tells `grep`'s "no match" (1) from its read error (2): an error naming the file, return 1; comment updated | RQ-07 |
| `routes.sh` | modified: an option with an empty key (`=x`) is refused as an unknown option before the `seen_options` lookup | RQ-11 |
| `README.md` | modified: "Accounts" — `build` is refused with the others and its sub-key/context/image/name rules go; `down` stops by project name without reading the file; `INFRA_HOST` no longer listed among the refused service names | RQ-02, RQ-04, RQ-09 |
| `docs/migration.md` | modified: the project's compose pulls images its CI pushed (no `build:`, refused by `sudo c4-app up` and `pull`) | RQ-01 |
| `tests/0011-facts.sh` | new (dev): `docker compose -p <p> down` with no file removes the project's containers and networks and keeps its volumes (exit 0 on an unknown project); an unchecked `down` of the hook fixture does run the hook (so AC-04's "no marker" means something); a throwaway Caddy: the admin probe answers while a refused `reload` fails, and fails on a stopped container | RQ-04, RQ-05 |
| `tests/0011-demo-host.stand-in.sh` | new: on the stand-in, `build.yml` refused by `up` and `pull` with RQ-01's message and nothing started; AC-04's `down` with the replaced file; a refused `INFRA_HOST` in the stack's `.env` no longer stops `c4-app up`; the six values read alike by `dotenv_value` and the demo's compose | AC-01, AC-04, AC-08, AC-09 |
| `tests/0011-up.sh` | new (dev, stubs, as `0003-up-reload.sh`): reload refused + probe answers → "refuses"; reload refused + probe fails, and `docker exec` failing → "isn't reachable" and not "refuses"; up.sh on a scratch copy without `certs/tls.crt` (throwaway `CA_DIR`) reaches `docker compose up` or stops with a message | AC-05, AC-10 |
| `tests/0011-scripts.sh` | new (dev): part `networks` (no daemon, no file, lock held from a `bash:5.2` container: waits, file never partial); part `dotenv` (grep stubbed to exit 2: refused naming the file; missing key still empty; the six values read alike by `dotenv_value` and `docker compose config`) | AC-06, AC-07, AC-08 |
| `tests/0003-routes.sh`, `tests/fixtures/0003/refused-empty-option-key.routes` | modified / new: `refused empty-option-key 3 "unknown option '=x'"` | AC-11 |
| `tests/0007-compose-check.stand-in.sh` | modified: the seven `build-*.yml` rows all expect RQ-01's message (the fixtures stay); header comment | AC-02 |
| `tests/fixtures/0011/` | new: `build.yml` (a valid Faito file with `build: .`), `down-hook.yml` + `hook.sh` (a refused file whose provider is a staged script writing a marker as root), `six-values.env` | AC-01, AC-04, AC-08 |
| `docs/intent/0011-…/plan.md`, `intent.md`, `docs/intent/README.md` | this plan; status `planned`; index row (by `/sdlc-plan approve`) | — |

## Order of work

0. **Setup**: in the 0011 worktree (the main one is on 0012 with uncommitted work: leave it), `git merge` 0012's and 0013's branches, or `origin/main` once they are merged; a green baseline. — skill: none — check: `git status --short` empty, `bash tests/run.sh --all` → `verification passed`.
1. **Spec v2** (the `down` contradiction, decided A on 2026-10-23): RQ-01, RQ-04, AC-01, Design, change log; approved by the product owner and tech lead with this plan. **Done**: commit 8398139. — skill: `sdlc-spec` — check: `git show --stat 8398139` is `spec.md` only.
2. **Facts**: `tests/0011-facts.sh`. A failing fact is a deviation before its step (fallback for `down`: keep the last checked model in the snapshot and run `down` from it). — skill: none — check: `bash tests/0011-facts.sh`.
3. **Failing tests**, one commit each, each shown failing for its reason, then frozen (`.claude/frozen-tests.local`, never committed): `test(0011): …`
   - 3a the build refusal, `down` of a refused project, the `INFRA_HOST` independence: `tests/0011-demo-host.stand-in.sh`, `tests/0007-compose-check.stand-in.sh`, `tests/fixtures/0011/` — check: both stand-in tests exit 1, KO on the new message, on AC-04's containers/networks, and on AC-09.
   - 3b `tests/0011-up.sh` — check: KO on "isn't reachable" and on the fresh clone's silent exit 1.
   - 3c `tests/0011-scripts.sh`, `tests/0003-routes.sh` and its fixture — check: KO on the lock (file written while held), on the unreadable `.env` (silent empty), on `=x` (`bad array subscript`); the RQ-08 guard passes.
4. **Fixes**, one commit each `fix(0011): …`, tests untouched:
   - 4a `demo/c4-app` checks (RQ-01, RQ-02, RQ-09) — check: `bash -n demo/c4-app`, `bash tests/0007-compose-check.stand-in.sh`, `bash tests/0011-demo-host.stand-in.sh` (AC-01, AC-02, AC-09 lines).
   - 4b `demo/c4-app` `down` (RQ-04) — check: `bash tests/0011-demo-host.stand-in.sh` (all).
   - 4c `up.sh` (RQ-05, RQ-10) — check: `bash tests/0011-up.sh && bash tests/0003-up-reload.sh`.
   - 4d `networks.sh` (RQ-06) — check: `bash tests/0011-scripts.sh networks && bash tests/0007-dev.sh rewrite`.
   - 4e `registry.sh` (RQ-07) — check: `bash tests/0011-scripts.sh dotenv && bash tests/0002-register-scope.sh && bash tests/0004-registry.sh`.
   - 4f `routes.sh` (RQ-11) — check: `bash tests/0003-routes.sh`.
5. **Docs**: `README.md`, `docs/migration.md` (the `c4-app` header was done in 4a/4b). — skill: none — check: `grep -n -E 'additional_contexts|build\.(network|tags)|a service that builds' README.md` finds nothing; reread against RQ-02, RQ-04, RQ-09.
6. **Verification**: unfreeze; mutation check (RQ-12/AC-12): `git checkout <step 3c commit> -- demo/c4-app up.sh networks.sh registry.sh routes.sh`, run the five new or changed tests → each KO, restore with `git checkout HEAD -- …`; then `bash tests/run.sh --all`, then `/sdlc-verify 0011`. — skill: `sdlc-verify` — check: `verification passed`.

## Risks

- `docker compose -p <app> down` with no file behaves differently on the demo's Compose → facts on dev (step 2), AC-04 on the stand-in (the demo's version); fallback above.
- `down` by name also removes containers the current file no longer declares → intended (RQ-04); volumes stay (no `-v`), the external `c4-infra.<app>` network stays.
- The post-hoc probe says "refuses" for a reload that failed on a hiccup while the proxy answers → Caddy's own message is printed first; the retry is the same command.
- The RQ-09 test edits the stack's `.env` on the stand-in → restored at once; a throwaway host, so no stack is left changed.
- An unreadable `.env` can't be made under Git Bash (`chmod` does nothing) → `grep` stubbed to exit 2: deterministic on both platforms.
- The lock needs `flock`, absent from Git Bash → the `bash:5.2` container as in `tests/0007-dev.sh` (`MSYS_NO_PATHCONV=1`, `cygpath -w`).
- 0012/0013 change the same scripts and the stand-in helpers → step 0 and its green baseline; a conflict with their changes is resolved on this branch only.
- Stand-in tests are slow → each fix step runs only its test; `--all` once, at the end.

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| AC-01 | automated test (stand-in) | `tests/0011-demo-host.stand-in.sh`: `build.yml`, `sudo c4-app up` and `pull` refused with RQ-01's message, no container, no `c4-infra.faito`. `down` is outside it (spec v2) |
| AC-02 | automated test (stand-in) | `tests/0007-compose-check.stand-in.sh`: the seven `build-*.yml` refused with the same message |
| AC-03 | automated tests (stand-in) | unchanged `tests/0007-isolation.stand-in.sh`, `0002-accounts.stand-in.sh`, `0003-demo-deploy.stand-in.sh`, and `valid.yml` in `0007-compose-check`: `bash tests/run.sh --all` |
| AC-04 | automated test (stand-in) | `tests/0011-demo-host.stand-in.sh`: valid project started, `down-hook.yml` swapped in, `sudo c4-app down`: containers and `faito_internal` gone, volume `faito_cache` kept, no marker; `tests/0011-facts.sh` shows the hook would run if the model were handed to compose |
| AC-05 | automated test | `tests/0011-up.sh`: the three outcomes; `tests/0003-up-reload.sh` unchanged |
| AC-06 | automated test | `bash tests/0011-scripts.sh networks` |
| AC-07 | automated test | `bash tests/0011-scripts.sh dotenv` |
| AC-08 | automated tests | `tests/0011-scripts.sh dotenv` (dev's compose), `tests/0011-demo-host.stand-in.sh` (the demo's) |
| AC-09 | automated tests | `tests/0007-compose-check.stand-in.sh` (`service-dotted-name.yml` refused by the name rule); `tests/0011-demo-host.stand-in.sh` (refused `INFRA_HOST` in `.env` no longer stops `up`) |
| AC-10 | automated test | `tests/0011-up.sh`, the fresh-clone case |
| AC-11 | automated test | `bash tests/0003-routes.sh`: `refused empty-option-key` |
| AC-12 | mutation check | step 6: the five scripts as of step 3c → the new tests KO; each failure also shown in its step 3 commit |

## Deviations

<!-- filled during implementation: date — what — why — impact on files or proof -->

- 2026-10-28 — step 0. `main` merged (45f9dda): 0012, 0013 and every later intent are in; the conflicts were the identifiers' renaming (ee97ed3), which `main` holds already: `main`'s side taken, the branch then differs from `main` by 0011's documents only. No new `--all` baseline: that tree is `main`'s, verified by 0024's `--changed --all` (26 tests) and the last milestone's `--all` (product owner's compression of 2026-10-27). Docker Compose is v5.3.0 here now.
- 2026-10-28 — step 3a. AC-09 can't be "a refused `INFRA_HOST` no longer stops `c4-app up`": `networks.sh ensure`, which `up` runs, reads `INFRA_HOST` on the demo host on purpose (the proxy's alias) and refuses it. The test asserts what the spec's AC-09 says, that c4-app's check reads no `INFRA_HOST` (its message `c4-app: INFRA_HOST of … can't be read` absent), and that `networks.sh` is then the one refusing it. The hook of AC-04 is staged by the earlier `up` (hook.sh sent first), so that the provider's executable exists where `down-hook.yml` names it: "no marker" then means compose wasn't handed the file. Steps 3b and 3c were committed before 3a (its stand-in run took longer). No impact on files.
- 2026-10-28 — steps 4a and 4b checked together: `tests/0011-demo-host.stand-in.sh` and `tests/0007-compose-check.stand-in.sh` run once after both (`every check passed`, each), not after each (a stand-in run takes six minutes); step 5's docs committed before 4d–4f (they don't depend on them).
- 2026-10-28 — step 6, review round (bootstrap: one; `code-review high`, `security-review`: no finding). `demo/c4-app`: the source directory is checked in `stage()` only, so that `down` needs nothing of the application's (RQ-04); its header says `down` works on no copy. `networks.sh`: the file's content is a function (`apps_yaml`) that `write_apps_file` writes to the temporary file before the rename, under `set -e` (a pipeline would have renamed a truncated file). `tests/0011-facts.sh` (not frozen: step 2's): host paths through `cygpath -w` under Git Bash, as CLAUDE.md asks; fact (b) is measured on Linux only (Windows' compose runs no shell script as a provider), and says so. No impact on files or proof.
- 2026-10-28 — step 6. The proof is `bash tests/run.sh --changed main --all` (43 of the 51 tests: every test the change concerns, stand-in and facts ones included), not `--all`: the product owner's rule of 2026-10-27 (CLAUDE.md, Verification); `--all` runs at the next milestone. AC-03's tests are among the 43.

## Verification

### Verification — 77782bc

- Verification command: `LC_ALL=C TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --changed main --all` at 77782bc → `total: 1101.2 s for 43 test(s)` / `verification passed (--changed: 43 of 51 tests)` (2026-10-28)
- Risk tier: high (what the demo host runs as root, `sudo c4-app`; the spec's tech lead agreement of 2026-10-23)
- Reviews: bootstrap mode: 1 round; bugs (`code-review high`) 8 findings, 4 fixed / 4 answered; security (`security-review`) no finding (`down` from `/` with the environment cleared reads no file of the application's, selects by the exact project label, runs no provider or hook; `build` caught after `docker compose config`'s normalisation; the other changes take no untrusted input); no `simplify` pass (bootstrap)
  - fixed (77782bc): `down` still required `~/<app>/<app>` (the check moved into `stage()`, `demo/c4-app`); `{ … } | write_apps_file` would have renamed a truncated file (the content is now `apps_yaml`, written under `set -e` before the rename, `networks.sh`); `tests/0011-facts.sh` gave host paths to the docker CLI without `cygpath -w` (CLAUDE.md); `c4-app`'s header said every command works on a copy
  - answered: `dotenv_value` still reads an `.env` it can't even stat as missing — AC-07 is a file that exists and can't be read; the stack's `.env` sits next to the scripts that read it (`registry.sh:75`)
  - answered: a reload that fails on a transient error while the admin API answers is reported as "refuses its configuration" — the plan's *Risks*: Caddy's message is printed first, and the fix and the retry are the same command (`up.sh:108`)
  - answered: AC-10's first check accepts any message on a failure — the second check (`certs/tls.crt` created) holds the pre-fix KO; the test is frozen (`tests/0011-up.sh:79`)
  - answered: `routes.sh` could record `seen_options` after validating the option instead of a special case for an empty key — a smaller change to a working loop; only an empty key is a bad subscript of an associative array (`routes.sh:142`)
- Mutation check (bug): at 6856e1a / b234695 (tests in, no fix): `tests/0011-demo-host.stand-in.sh` → `10 check(s) failed` (AC-01 builds as root, `failed to solve: failed to read dockerfile`; AC-09 `c4-app: INFRA_HOST of … can't be read`; AC-04 down refused), `tests/0007-compose-check.stand-in.sh` → `7 check(s) failed`, `tests/0011-up.sh` → `6 check(s) failed` (with a certificate issued: AC-05 `docker exec failing → "refuses its configuration"`), `tests/0011-scripts.sh` → `4 check(s) failed`, `tests/0003-routes.sh` → `2 check(s) failed` (`seen_options: bad array subscript`)
- Verifier: 12/12 criteria OK — table below; neighbouring flows: `networks.sh compose-file` on the real daemon in a scratch copy writes the same `compose.apps.yml` (mode 0644, no temporary file left), `docker compose config --quiet` exit 0; `tests/0003-up-reload.sh` `every check passed`; 0002-accounts' `down` stops Faito's containers, not Hurura'a's nor the stack's
- Not verifiable here: none
- Files outside the plan: none
- Pre-existing findings (not fixed, out of scope): `stage()` runs before `check_model`, so a refused `up` or `pull` still syncs the refused files into `/var/lib/c4-apps/<app>/`, which the running containers mount (RQ-01's "nothing changed" holds for containers only) → bug intent suggested; the header comments of `tests/fixtures/0007/hostile/build-*.yml` still give their former reasons (a detail)

| Criterion | Result | Evidence |
| --- | --- | --- |
| AC-01 | OK | `0011-demo-host.stand-in`: `ok - AC-01: build.yml: sudo c4-app up is refused`, `… it says "c4-app: refused: service gateway: build: the demo host runs the images the application's CI pushes to a registry"`, `… no network c4-infra.faito was created`, `… sudo c4-app pull is refused` |
| AC-02 | OK | `0007-compose-check.stand-in`: the seven `build-*.yml` say RQ-01's message, `every check passed` |
| AC-03 | OK | `0007-isolation.stand-in` `ok - Hurura'a starts`, `ok - Faito starts`; `0002-accounts.stand-in` pull and up exit 0; `0003-demo-deploy.stand-in` `every check passed` |
| AC-04 | OK | `0011-demo-host.stand-in`: down exits 0, no container, `faito_internal` gone, `faito_cache` and `c4-infra.faito` kept, no `hook-ran`; `0011-facts` (b): an unchecked down does run the provider (Linux) |
| AC-05 | OK | `0011-up`: "refuses" when the admin API answers, "isn't reachable" and never "refuses" otherwise; `0011-facts` (c) on a real Caddy; `0003-up-reload` unchanged, passing |
| AC-06 | OK | `0011-scripts networks`: waits while the lock is held, writes nothing meanwhile, then `services: {}`, no temporary file (the rename on that path read in the code, not failing first) |
| AC-07 | OK | `0011-scripts dotenv`: `fails (exit 1)`, names the file; a missing key reads empty, exit 0; the verifier also on a real `chmod 000` file |
| AC-08 | OK (guard) | alike on dev (Compose v5.3.0) and on the stand-in |
| AC-09 | OK | `service-dotted-name.yml` refused by the name rule; `ok - AC-09: a refused INFRA_HOST: c4-app's check doesn't read it` |
| AC-10 | OK | `0011-up`: a fresh clone reaches `docker compose up`, `certs/tls.crt` created |
| AC-11 | OK | `0003-routes`: `refused empty-option-key` exits 1, names line 3, says `unknown option '=x'`, prints no site |
| AC-12 | OK | mutation check above: each test KO before its fix |
