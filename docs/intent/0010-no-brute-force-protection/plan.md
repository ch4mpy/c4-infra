# Plan: No realm of the shared Keycloak protects its accounts against password guessing

- Spec: [v2](spec.md)
- Status: approved
- Branch: 0010-no-brute-force-protection
- Approved: 2026-10-23, Jérôme Wacongne (engineer, and tech lead for the high risk; also the product owner), after a fresh-context review of the plan against the code (13 findings folded in)
- Builds on: **0009** (`keycloak-import/master-realm.json`): implemented once 0009 is merged into `main` (step 0: `git merge origin/main`); started earlier, the `0009-master-realm-sends-no-mail` branch is merged into this one instead (recorded as a deviation). Also 0006 (`tests/lib/keycloak.sh`: `kc_admin`, `kc_registration`), 0004 (`REGISTRY_FILE` fixtures).

## Starting point

- `register-app.sh:270-273` imports a realm with `kcadm -i create realms -f - -s "realm=$realm" < "$file"`: kcadm's `-s` overrides the file's attributes; a realm already there is "left as it is"; `--reset-realms` deletes it first. `register-app.sh` doesn't use `jq` (the developers' workstations needn't have it): the settings go as `-s` options.
- Keycloak's temporary lockout (docs): linear wait = `waitIncrementSeconds × (1 + count − failureFactor)`, capped by `maxFailureWaitSeconds`; two failures less than `quickLoginCheckMilliSeconds` apart lock for `minimumQuickLoginWaitSeconds`; a success resets the count; the admin API's `attack-detection/brute-force/users/<id>` reports `disabled` and `numFailures`.

## Files

| File | Change | For |
| --- | --- | --- |
| `keycloak-import/master-realm.json` | modified: `bruteForceProtected` true, `permanentLockout` false, `maxTemporaryLockouts` 0, `failureFactor` 10, `bruteForceStrategy` `LINEAR`, `waitIncrementSeconds` 60, `maxFailureWaitSeconds` 900, `maxDeltaTimeSeconds` 43200, `quickLoginCheckMilliSeconds` 1000, `minimumQuickLoginWaitSeconds` 60 | REQ-1, REQ-4, REQ-6 |
| `register-app.sh` | modified: one array of the same ten `key=value` (comment: the same values as `keycloak-import/master-realm.json`, checked by `tests/0010-brute-force.sh`), passed as `-s` options to the import **after** `-s "realm=$realm"` (`tests/0002-register-scope.sh:97` looks for `create realms -f - -s realm=faito`); a line `Realm <r>: brute-force protection set`; a realm already there unchanged | REQ-1, REQ-2, REQ-3, REQ-6 |
| `README.md` | modified: "Brute-force protection" (the settings, every realm; the master realm at its creation; an application's realm at its import, whatever its export says; a realm registered before gets them with `--reset-realms`; an administrator unlocks an account in the console) | REQ-8 |
| `docs/migration.md` | modified: one line where the realm export is described: its brute-force settings are replaced at import | REQ-8 |
| `tests/fixtures/0010/registry.txt` | new: the real entries plus `34 verif-lockout verif-lockout - - verif-lockout.dev.localhost verif-lockout.c4-soft.com` | AC-2, AC-3, AC-5 |
| `tests/fixtures/0010/verif-lockout-realm.json` | new: realm `verif-lockout` with detection off and `failureFactor` 30, a user `visitor` (a public test password), a public client `verif-cli` with direct access grants | AC-2, AC-3, AC-5 |
| `tests/0010-brute-force.sh` | new, dev side: a throwaway Keycloak (`--db=dev-file`) importing `keycloak-import/` (as `tests/0009-master-realm.sh`): master's settings, kept across a restart when changed (AC-1, AC-4); on the dev stack, the fixture realm through `register-app.sh` with `REGISTRY_FILE`: imported → REQ-1's settings, equal to master's (AC-2); then turned off by the registration account (`kc_registration update realms/verif-lockout -s bruteForceProtected=false`), registered again → still off, `--reset-realms` → REQ-1 (AC-5); first lockout (AC-3); `kc_registration update realms/master -s bruteForceProtected=false` → 403 (AC-8); the `EXIT` trap deletes the realm and, when the test created it, the network (`bash networks.sh remove verif-lockout`, as `tests/0006-account.sh:36-53`) | AC-1 to AC-5, AC-7, AC-8 |
| `tests/0010-brute-force.stand-in.sh` | new: the stand-in host's first deployment → master's settings (AC-1, demo side); `bash tests/0006-bootstrap-admin-replaced.stand-in.sh` and `tests/0009-master-realm.stand-in.sh` still pass under the lockout | AC-1 |
| `docs/intent/0010-no-brute-force-protection/plan.md` | new: this plan (`approved` at the gate) | bookkeeping |
| `docs/intent/0010-no-brute-force-protection/intent.md` | modified: status `planned` | bookkeeping |
| `docs/intent/README.md` | modified: index row 0010 → `planned` | bookkeeping |

## Order of work

0. **0009 in**: `git merge origin/main` once 0009 is merged (else the 0009 branch, as a deviation). — skill: none — check: `test -f keycloak-import/master-realm.json`.
1. **Settings in both places**: `keycloak-import/master-realm.json`, `register-app.sh`, the fixtures, `tests/0010-brute-force.sh` without the timing part. — skill: none — check: `bash tests/0010-brute-force.sh && bash tests/0006-account.sh && bash tests/0009-master-realm.sh`.
2. **First lockout** (AC-3, the engineer's choice: the first lockout only, about 75 s) in `tests/0010-brute-force.sh`: as `visitor` through `verif-cli` (kcadm `config credentials --realm verif-lockout --client verif-cli`, password in `KC_CLI_PASSWORD`), 9 wrong passwords 1.2 s apart → not `disabled`; the 10th → `disabled`, the right one refused; at +61 s the right one logs in. The linear growth (2 minutes after an 11th failure) is proven by the settings (`LINEAR`, `waitIncrementSeconds` 60) and Keycloak's documented formula. — skill: none — check: `bash tests/0010-brute-force.sh`.
3. **Demo host**: `tests/0010-brute-force.stand-in.sh`. — skill: none — check: `bash tests/0010-brute-force.stand-in.sh && bash tests/0009-master-realm.stand-in.sh && bash tests/0006-bootstrap-admin-replaced.stand-in.sh`.
4. **Docs**: README, `docs/migration.md`. — skill: none — check: `bash tests/run.sh --all`.
5. **This workstation's re-creation again** (as 0009's step 6, announced first), so that its master realm gets the brute-force settings; Faito's realm, imported again, gets them too. No commit. — skill: none — check: `kc_admin get realms/master --fields bruteForceProtected,failureFactor,bruteForceStrategy` and the same for `faito` show REQ-1's values.

## Risks

- The lockout locks the stack's or the tests' own administrator (a stale bootstrap password tried at each repair, two failures within 1 s → 60 s) → the stack logs in as an administrator only to repair the registration account, one try per candidate (0006); step 3 re-runs the stand-in tests that replace and delete administrators.
- The values live in two files → `tests/0010-brute-force.sh` compares the imported master realm's settings with the registered realm's.
- An application's own settings replaced without notice → `register-app.sh`'s line, README, `docs/migration.md`.
- The timing test adds about 75 s to `tests/run.sh` → failures spaced 1.2 s (quick-login rule), one bounded wait.
- A failed run leaves `verif-lockout` (realm, network `c4-infra.verif-lockout`, `compose.apps.yml` entry) on the dev stack → removed by the `EXIT` trap, and before the run if present.

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| AC-1 | automated test | `tests/0010-brute-force.sh` (throwaway, dev values), `tests/0010-brute-force.stand-in.sh` (demo) |
| AC-2 | automated test | `tests/0010-brute-force.sh`: fixture realm imported → REQ-1's ten values, equal to master's |
| AC-3 | automated test + command | `tests/0010-brute-force.sh`, step 2: not locked after 9 failures, locked after 10, the right password refused, then accepted at +61 s; the 2-minute wait after an 11th failure by the settings asserted (`LINEAR`, 60 s) and Keycloak's documented formula |
| AC-4 | automated test | `tests/0010-brute-force.sh`: master's changed settings survive a restart |
| AC-5 | automated test | `tests/0010-brute-force.sh`: a realm already there with its detection off stays off at registration, `--reset-realms` → REQ-1 |
| AC-7 | command | `permanentLockout` false, `maxTemporaryLockouts` 0, `maxFailureWaitSeconds` 900 on master and on the registered realm (asserted by the test); Keycloak's documented temporary-lockout algorithm releases at most 900 s after the last failure (a 15-minute wait isn't run) |
| AC-8 | automated test | `tests/0010-brute-force.sh`: 403 |

## Deviations

- 2026-10-23 — step 0: 0009 isn't merged into `main` yet (its delivery is the human's): the branch `0009-master-realm-sends-no-mail` is merged into this one instead, as planned for that case; this PR shows 0009's commits until 0009 is merged. Implemented in a worktree, as 0009 (its plan's deviation): `tests/0006-account.sh` and the dev-stack checks run with the full suite in `D:\workspaces\c4-infra`.
- 2026-10-23 — spec v2 (PA-3, raised by the security review of the implementation, decided by the product owner: no lockout on the master realm). `keycloak-import/master-realm.json` is no longer modified (its row in *Files* drops); `tests/0010-brute-force.stand-in.sh` is dropped (it only checked the master realm's settings on the stand-in: `register-app.sh` is the same script on both hosts, AC-2 on the dev stack covers it), and with it step 3; step 5 (this workstation's re-creation, for the master realm's settings) has nothing left to apply. `tests/0010-brute-force.sh` checks the dev stack's master realm (AC-1: no detection) instead of a throwaway Keycloak; AC-4 is gone (spec v2). The README section says the master realm has none, and names Keycloak's quick-login rule (the bug review). Steps 1 and 2 land in one commit (the same test file).
- 2026-10-23 — the reviews' findings answered without a change: a shared `kc_wait_ready` helper (the throwaways are 0009's, and `tests/lib/keycloak.sh` is shared with the other session's work on 0001–0008); a `stand_in_env_rewrite` helper in `tests/lib/stand-in-host.sh` (it would change `tests/0006-bootstrap-admin-replaced.stand-in.sh`, 0006's, out of this change's scope).
- 2026-10-23 — review round 2: spec v2 also voids the plan's comparisons with the master realm (*Proof* AC-2 "equal to master's", AC-7 "on master and on the registered realm", the *Risks* line on two files holding the values): the test checks the registered realm against REQ-1's values only, and AC-1 that the master realm's import sets no detection and the dev stack's master realm has none. The docs say every administrator of the master realm gets a generated password (nothing limits guessing there); AC-8's probe writes a value that changes nothing; the fixture's network is removed whether or not this run created it. The merge of 0009's round 2 (02b6e71) carries 0010's two README passages on administrators' passwords ("The registration account" and "Brute-force protection"), written while resolving a conflict in that file. Review round 3: those passages limited to the demo host (dev's `.env` password is `secret`, on the loopback); the round cap reached, these doc-only fixes aren't reviewed again.
- 2026-10-23 — verifier: the *Files* and *Proof* tables above are the approved plan's; as amended by spec v2 and the lines above, `docs/demo-setup.md` (step 5: generated passwords for every administrator of the master realm) is changed too, and the proofs are `tests/0010-brute-force.sh` alone: AC-1 the import sets no `bruteForceProtected` and the dev stack's master realm has none, AC-2/AC-5/AC-7 the registered realm against REQ-1's ten values, AC-3 the first lockout, AC-8 a 403; AC-4 and the stand-in test are gone.
- 2026-10-23 — rebased onto the rebased 0009 (itself onto `main` at `feb8c02`), at the engineer's request: the merges of 0009 into this branch are gone (a linear history on 0009's tip). Conflicts: `register-app.sh`, whose login and import `main` now does with `registration-account.sh`'s functions (`account_login`, `account`): `brute_force` and its line go into that code; the README, where the passages of review rounds 2 and 3 are applied to `main`'s text. The rebase added one index row per status: fixed by its own commit. The rebased tree equals the rebased 0009 plus this change's former own diff, but for the index row's place (checked with `git apply --3way`). The gates' commits named in the PR's comments have new hashes.
