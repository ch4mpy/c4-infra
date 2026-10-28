# Plan: A deployment that pulls a new database image recreates the database under a running Keycloak, and the registration check then blames the administrator

- Spec: none, the [intent](intent.md) (bug, spec needed: no)
- Status: approved
- Branch: 0024-database-image-change-under-keycloak
- Approved: 2026-10-28, Jérôme Wacongne (engineer; the images keep their tags, product owner)

## Starting point

Deploy-demo run 40636936869 (2026-10-28): `postgres:18.6` republished upstream, `c4-infra.keycloak-db` recreated while `c4-infra.keycloak` kept running, then `registration-account.sh ensure` failed and blamed the administrators. Read (2026-10-28):
- `demo/deploy.sh:35-42` stops Keycloak (after a dump) only when Keycloak's own image changes; `:45`'s `docker compose up -d --remove-orphans --wait` recreates any other service whose image or settings changed, the database included, under a running Keycloak; `--wait` takes Keycloak's healthy state from before.
- `registration-account.sh:223` (`ensure`): any failure of `account_login` (kcadm's `config credentials`, output in `$login_output`) is taken for a missing account or a secret that isn't `.env`'s, and leads to `login_administrator`, whose last message (`:158-163`) blames the bootstrap administrator and `KC_SETUP_ADMIN_*`.
- The product owner keeps the images' tags (2026-10-28): an upstream rebuild still reaches the next deployment, which must take it safely.

## Engineer's choices

- `deploy.sh` brings Keycloak's database up first, on its own; when its container changed (another id) while Keycloak runs, it restarts Keycloak on it before anything else, saying so; Keycloak's sessions are persistent, so they survive the restart.
- `registration-account.sh` tells a refusal (the credentials: kcadm's message for an unknown client or a wrong secret, measured at step 0) from a Keycloak that doesn't answer (anything else): the latter is retried for 60 s, then reported as such, never as an administrator's fault.
- The reproducing test asserts what doesn't depend on timing: after a deployment that recreated the database, Keycloak started after it; and the deployment's success and its registration check.

## Files

| File | Change | For |
| --- | --- | --- |
| `demo/deploy.sh` | modified: the database's container id before; `docker compose up -d --wait keycloak-db`; a changed id with Keycloak running → `docker compose restart keycloak`, then the full `up --wait` as today; the Keycloak-image path (dump, stop) unchanged | the outcome (the database replaced without Keycloak losing it) |
| `registration-account.sh` | modified: `account_login`'s and `admin_login`'s failures sorted into a refusal and no answer; no answer retried 60 s, then `Keycloak doesn't answer …: its administrators aren't at fault (above)`, exit 1 | the outcome (the check tells a Keycloak that doesn't answer) |
| `tests/0024-db-image-change.stand-in.sh` | new, frozen after step 1: a stand-in deployed (`stand_in_accounts`), then `postgres:18.6` replaced in its Docker by an image built on it (a label), the deployment run again: it exits 0, says the registration account is up to date, Keycloak started after its database, a realm's discovery answers; then Keycloak's database stopped under a running Keycloak, `registration-account.sh ensure` says Keycloak doesn't answer, not that an administrator fails | the outcome |
| `README.md` | modified: the demo deployment's paragraph says a new image of Keycloak's database recreates it and restarts Keycloak on it | the outcome (the operator reads what happens) |
| `docs/intent/0024-…/plan.md`, `intent.md`, `docs/intent/README.md` | this plan; status planned, then delivered; the index row | — |

## Order of work

0. **Setup and facts**: `git merge main`; on the dev stack, kcadm's message for a wrong client secret (`config credentials` with the registration account and a wrong secret) and for no answer (`--server` on a closed port); in a stand-in deployed by `stand_in_accounts`, `postgres:18.6` replaced by an image built on it, `deploy.sh` run again over ssh as `c4-infra`, three times: the output (`keycloak-db Recreate`, `keycloak Running`), `account_login`'s message when it fails. — skill: none — check: the messages and the outcome recorded in *Deviations*.
1. **Failing test**: `tests/0024-db-image-change.stand-in.sh`. — skill: none — check: `bash tests/0024-db-image-change.stand-in.sh` exits 1 on "Keycloak started after its database" (and on the deployment's exit and the message when step 0 reproduced them), three runs. Commit `test(0024): …` alone, freeze it.
2. **Fix `deploy.sh`**. — skill: none — check: the test's deployment checks `ok`; `bash tests/0003-demo-deploy.stand-in.sh` and `bash tests/0013-upgrade.stand-in.sh` (a Keycloak image change: its dump, its stop) `every check passed`. Commit `fix(0024): …`.
3. **Fix `registration-account.sh`**. — skill: none — check: `bash tests/0024-db-image-change.stand-in.sh` `every check passed`, three runs; `bash tests/0006-account.sh` (the account's creation and rotation in dev, a refused secret) `every check passed`. Commit `fix(0024): …`.
4. **Docs**: README. — skill: none — check: reread. Commit `docs(0024): …`.
5. **Verification**: `LC_ALL=C TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --changed --all` (the tests that declare `demo/` or `registration-account.sh`: most of the suite); mutation check: step 1's `deploy.sh` in a worktree → the test `KO`; `/sdlc-verify 0024` (bootstrap: one round; the security pass too if the risk is high: `registration-account.sh` handles the registration account's secret), its evidence into `## Verification`. — skill: sdlc-verify — check: `verification passed`. Then `/sdlc-ship 0024`: the push deploys the demo host, whose run must pass (after deployment: its log has `Registration account c4-infra-registration: up to date`).

## Risks

- Restarting Keycloak during a deployment logs nobody out (persistent sessions, Keycloak 26) but interrupts it for its restart → only when its database's container changed, which already interrupts it today.
- A new major version of the database (18 → 19) needs a migration this plan doesn't do → out of scope; the tag names the major version, which only the stack changes.
- kcadm's messages change with Keycloak's version → measured at step 0 on 26.8.1; an unknown message counts as no answer, which is retried, then reported without blaming the administrators.
- The reproducing test replaces `postgres:18.6` in the stand-in's Docker, whose volume keeps images between runs → the test removes its image at its end; `stand_in_up` keeps pulled images, so the next run pulls the real one when the tag is gone.

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| A deployment that replaces the database's image passes, Keycloak working with the new database | automated test + after deployment | `tests/0024-db-image-change.stand-in.sh` (exit 0, Keycloak started after its database, `up to date`, a discovery answering); the push's deploy-demo run passing |
| The check tells a Keycloak that doesn't answer from an account or administrator that doesn't work | automated test | `tests/0024-db-image-change.stand-in.sh` (the database stopped: "doesn't answer", no administrator blamed); `tests/0006-account.sh` (a refused secret still leads to the administrator's path) |
| The Keycloak upgrade's dump still comes first | automated test | `tests/0013-upgrade.stand-in.sh` `every check passed` |
| The bug is reproduced | mutation check | step 1's `deploy.sh` → the test `KO` (step 1, and in a worktree at step 5) |

## Deviations

<!-- filled during implementation: date — what — why — impact on files or proof -->

- 2026-10-28 — step 0. kcadm 26.8.1, `config credentials`: a wrong client secret → `Invalid client or Invalid client credentials [unauthorized_client]`; an unknown client → `… [invalid_client]`; a wrong administrator password → `Invalid user credentials [invalid_grant]`; a closed port → `Failed to send request - Connect to localhost:1 … failed: Connection refused`. In a stand-in deployed by `stand_in_accounts faito`, `postgres:18.6` replaced three times by an image built on it, `deploy.sh` run again as `c4-infra`: round 1 exit 1 with the demo's message ("No administrator of Keycloak's master realm could log in to create the registration account …"); round 2 exit 0, `up to date`; round 3 exit 0 after `its secret set to .env's` (a needless repair: the account's login failed, the stand-in's bootstrap administrator still works); Keycloak never restarted (started 06:54:52, its database 06:55:24, 06:55:41, 06:56:03). The reproducing test asserts the restart (deterministic), and the deployment's exit and the absence of a repair (each failing now and then). No impact on files.
- 2026-10-28 — step 3. Keycloak's database stopped under a running Keycloak (stand-in): kcadm's `config credentials`, as the account and as the bootstrap administrator, fails in about 1 s with `For more on this error consult the server log. [unknown_error]`, at once and 20 s later. A refusal is told by kcadm's OAuth error code (`[unauthorized_client]`, `[invalid_client]`, `[invalid_grant]`) rather than by its English message: the codes are the protocol's, the messages Keycloak's. `register-app.sh` keeps its single login attempt (not in *Files*); its message for a Keycloak that doesn't answer is unchanged. Step 2's `tests/0013-upgrade.stand-in.sh` ran with step 3's `registration-account.sh` already in the working tree. No impact on the proof.
- 2026-10-28 — step 5, review round (bootstrap: one). `deploy.sh`: the database comes up once, before the Keycloak-image check (no second `up keycloak-db`), with `--wait-timeout 300` and `docker compose ps` on failure as the full `up`; Keycloak is restarted when the database's container id **or its start time** changed (a database stopped and started again, not only recreated); the restart is the `elif` of the image change (Keycloak stopped then). Comments shortened. No impact on files or proof.
- 2026-10-28 — step 5, proof run. `tests/0002-register-scope.sh` KO on "the bootstrap password refused: says so": its fake docker refused the account's login with a silent `exit 1`, which the new `refused()` takes for no answer (retried 60 s, then "Keycloak doesn't answer"). The fake now prints kcadm's refusal as kcadm 26.8.1 does (`… [unauthorized_client]`, step 0); the test's checks are unchanged. File outside *Files*: `tests/0002-register-scope.sh` (its fake only).

## Verification

### Verification — cc5c7de

- Verification command: `LC_ALL=C TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --changed --all` at 49e7ce6 → `total: 1014.3 s for 26 test(s)` / `FAILED: tests/0002-register-scope.sh` (its fake docker, fixed in cc5c7de, *Deviations*); then `bash tests/run.sh --changed 49e7ce6` at cc5c7de → `verification passed (--changed: 1 of 47 tests)` (2026-10-28)
- Risk tier: high (authentication and secrets: `registration-account.sh` decides when to log in as an administrator, and handles the registration account's secret)
- Reviews: bootstrap mode: 1 round; bugs (`code-review high`) 10 findings, 4 fixed / 6 answered; security (`security-review`) no finding (secrets still passed by name, no secret in kcadm's printed output, a misclassified failure fails closed or takes the repair path that existed before); no `simplify` pass (bootstrap)
  - fixed (49e7ce6): `up -d --wait keycloak-db` without `--wait-timeout` nor `docker compose ps` on failure (`demo/deploy.sh:34`); written twice (the image path and the new one: now once, before both); a database stopped and started again (same container id) didn't restart Keycloak: its start time is compared too (`demo/deploy.sh:31`); comments shortened
  - answered: dev's `up.sh` can recreate the database under Keycloak too — `up.sh` pulls no image, so the trigger (an image republished under its tag) doesn't arise in dev; a compose-level `depends_on: keycloak-db: {restart: true}` would cover both, a follow-up to measure (`up.sh:99`)
  - answered: an unknown kcadm output no longer falls through to `KC_SETUP_ADMIN_*` — intended (plan, *Risks*): retried, then reported with kcadm's lines; a refusal's codes are the protocol's, and the 0006 tests (a real Keycloak) run on any change of the script (`registration-account.sh:66`)
  - answered: Keycloak restarted, then recreated again by the full `up` when its own settings changed in the same deployment — rare, a few seconds more of restart (`demo/deploy.sh:49`)
  - answered: a credential typed at the terminal waits up to 60 s while Keycloak doesn't answer — the account's login just went through the same wait, so Keycloak answered moments before (`registration-account.sh:103`)
  - answered: the frozen test compares `StartedAt` strings lexically, and checks "recreated" by start time, not id — the database's healthcheck puts seconds between the two starts; the image replaced forces a recreation (`tests/0024-db-image-change.stand-in.sh:50,64`; frozen, unchanged)
- Mutation check (bug): `tests/0024-db-image-change.stand-in.sh` fails at 126d101 (the test, no fix), in a throw-away worktree: `KO - the deployment runs again and exits 0` (the incident's message), `KO - Keycloak started after its database`, `KO - saying Keycloak doesn't answer` … `5 check(s) failed`, `exit 1`
- Verifier: 4/4 criteria OK — table below; neighbouring flows: `registration-account.sh ensure` on the dev stack → `Registration account c4-infra-registration: up to date`; `refused()` / `until_answered` exercised without docker (a refusal returns 1 at once, no answer exits 1 after the timeout, an answer on the 3rd try returns 0); `0006-bootstrap-admin-replaced` and `0009-master-realm` (stand-in) still reach the administrator's messages
- Not verifiable here: the push's deploy-demo run passing (its log with `Registration account c4-infra-registration: up to date`): after deployment, for the product owner (main not pushed tonight)
- Files outside the plan: `tests/0002-register-scope.sh` (its fake docker only; *Deviations*)
- Pre-existing findings (not fixed, out of scope): `register-app.sh:407` reports a Keycloak that doesn't answer as "The registration account … doesn't log in" (single attempt) → follow-up suggested

| Criterion | Result | Evidence |
| --- | --- | --- |
| A deployment that replaces the database's image passes, Keycloak working with the new database | OK (deploy-demo run: after deployment) | `tests/0024-db-image-change.stand-in.sh` in the full run: `ok - the deployment runs again and exits 0`, `ok - Keycloak started after its database`, `ok - the registration account is up to date`, `ok - the master realm's discovery answers`, `every check passed`; three more runs at step 3 `every check passed` |
| The check tells a Keycloak that doesn't answer from an account or administrator that doesn't work | OK | same test, its database stopped: `ok - saying Keycloak doesn't answer`, `ok - not that an administrator doesn't log in`; `tests/0006-account.sh` (a real refusal still repaired: `its secret set to .env's`) `every check passed` |
| The Keycloak upgrade's dump still comes first | OK | `tests/0013-upgrade.stand-in.sh`: `ok - AC-07: dumped before Keycloak stops`, `every check passed` |
| The bug is reproduced | OK | mutation check above: `5 check(s) failed` at 126d101 |

After deployment: the push's deploy-demo run (its log with `Registration account c4-infra-registration: up to date`) is not done: `main` stays local tonight (2026-10-28), pushed once the product owner validates the night's work; the run is checked then.

### After deployment — deploy-demo run 40684696927 on `main` fc47b85 (2026-10-28, the product owner's push), success

- Its log: `Registration account c4-infra-registration: up to date`; Keycloak's image changed in the same deployment (0016): `its database dumped, Keycloak stopped first`, the dump `c4-infra-keycloak-before-upgrade-20261028-120430.dump`. The failed run 40636936869 is superseded.
