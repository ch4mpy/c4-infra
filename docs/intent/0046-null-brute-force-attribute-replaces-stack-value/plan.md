# Plan: A brute-force setting an export's attributes hold as null replaces the stack's value, while the registration names the stack's

- Spec: [v1](spec.md)
- Status: approved
- Branch: `main` (bootstrap mode, no other intent in progress)
- Approved: 2026-10-30, Jérôme Wacongne (the product owner's one-pass decision of 2026-10-30, as for 0040 to 0045)

## Files

| File | Change | For |
| --- | --- | --- |
| `tests/0004-registry.sh` | modified: its `scripts` part, 0046's cases (refused in dev and on the demo host, accepted ones), its header | AC-01, AC-02 |
| `register-app.sh` | modified: `stack_brute_force` defined before the realm checks, `null_check` beside `lockout_check`, its refusal, its header | RQ-01, RQ-02 |
| `README.md`, `docs/migration.md` | modified: the refusal stated | RQ-03, AC-03 |
| `docs/intent/0046-…/`, `docs/intent/README.md`, `docs/intent/HANDOVER.md` | intent, spec, plan; the index row; the handover at delivery (its "Left open" line removed) | — |

## Order of work

1. Failing test — skill: none — check: `TMPDIR=~/.cache/c4-infra-tests bash tests/0004-registry.sh scripts`: the refused cases KO (`… it says why`, `… no docker call`), the accepted ones `ok`; commit `test(0046): …`.
2. The check — skill: none — check: the same, `every check passed`; the six real exports pass; commit `fix(0046): …`.
3. Docs — skill: none — check: read; commit `docs(0046): …`.
4. Review — one round, a fresh agent (bugs and security, the risk being high), on the diff since the plan's commit.
5. Verification — `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --changed --all` from the main checkout, the evidence below; then delivery (`intent: 0046 delivered`, the handover, push, the deployment followed).

## Risks

- The refusal fires on a real export → the six real exports checked at step 2 (none holds a null attribute).
- A null attribute outside the ten refused by mistake → AC-02's `frontendUrl: null` case.

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| AC-01 | automated test, mutation | `tests/0004-registry.sh` `scripts`, 0046's refused cases; KO at step 1's commit |
| AC-02 | automated test | the same, 0046's accepted cases |
| AC-03 | reading | README "Brute-force protection", `docs/migration.md` step 4 |
| No regression | command | `bash tests/run.sh --changed --all`, `verification passed` |

## Deviations

- 2026-10-30 — step 1 (9a78658): `tests/0004-registry.sh scripts` from the main checkout, `7 check(s) failed`, the refused cases' `… it names attributes.<setting>` and `… no docker call`, the two accepted cases `ok` (`~/.cache/c4-infra-tests/0046-before.log`). Step 2 (9381f76): `every check passed`, 78 `ok` (`0046-after.log`); the six real exports and the fixtures of `tests/fixtures/` pass `null_check`.
- 2026-10-30 — step 4, the review (a fresh agent, bugs and security): 0 Important, 1 detail, README said the attribute is refused where the export is, fixed in c8a73f3. Answered, out of scope: an attribute given as `""` gets Keycloak's default too (`RealmModel.getAttribute`, `!v.isEmpty()`), the registration then naming the setting as the export's, which it is; on the demo host, `lockout_check` refuses `""` for its three settings.

## Verification

### Verification — c8a73f3

- Verification command: `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --changed 6b4720c --all`, from the main checkout on `main` at c8a73f3, one stand-in lane → `total: 1814.5 s for 36 test(s)`, `verification passed (--changed: 36 of 84 tests)`, `run.sh exit 0`, no `KO` line (2026-10-30, `~/.cache/c4-infra-tests/0046-changed-all.log`).
- Risk tier: high (authentication: the brute-force protection of the applications' realms).
- Reviews: bootstrap mode: 1 round, on `6b4720c..befc06a`, bugs and security in one fresh agent: 0 Important, 1 detail fixed (Deviations); checked and found to hold: the move of `stack_brute_force` and `stack_keys` (the same values for the probe and the import, set with no realm too under `set -u`, `null_check`'s variables local), odd inputs (`"null"`, an empty key, the key's case, `attributes` null or an array, duplicate keys), `IN` and `split/1` since jq 1.6, the refusal before `networks.sh ensure`, the ten names as Keycloak's (`RealmAdapter`), the tests failing without the fix for the right reason; the comments the diff adds give reasons and sources.
- Mutation check (bug): `tests/0004-registry.sh scripts` at 9a78658, before the fix: `7 check(s) failed` (`0046-before.log`).
- Verifier: not run (the product owner's one-pass decision, as for 0040 to 0045).
- Not verifiable here: none.
- Files outside the plan: none.
- Agent configuration: not changed (the intent home's `Mode` line comment aside, a fact of the product owner's), no eval report.
- Pre-existing findings (not fixed, out of scope): an attribute given as `""` (Deviations).

| Criterion | Result | Evidence |
| --- | --- | --- |
| AC-01 | OK | the run, `tests/0004-registry.sh`: in dev, `bruteForceProtected` null, then `failureFactor` and `maxFailureWaitSeconds` null (both named); on the demo host, `failureFactor` null: each `refused (exit non-zero)`, `it names attributes.<setting>`, `no docker call` `ok`; KO at 9a78658 |
| AC-02 | OK | the same: `{"realm": "faito", "bruteForceProtected": null}` and `{"realm": "faito", "attributes": {"frontendUrl": null}}`, in dev, `past the export's checks` `ok` |
| AC-03 | OK | read: `README.md:395-399`, `docs/migration.md:226-229` |
| No regression | OK | the run above, 36 tests, `verification passed` |
