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

## Verification
