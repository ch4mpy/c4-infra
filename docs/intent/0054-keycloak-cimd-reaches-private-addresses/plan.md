# Plan: Keycloak fetches a client's metadata document from a private address when a trusted domain resolves to one

- Spec: [v2](spec.md) (approved 2026-11-01: PA-01 B, PA-02 A, PA-03 B, PA-04 A, PA-05 A moot)
- Status: approved
- Branch: `0054-keycloak-cimd-reaches-private-addresses`
- Approved: 2026-11-01, Jérôme Wacongne (engineer and tech lead, recorded once; the plan's one choice, where the 27.x work goes, decided by him and relayed by the coordinating session)

## Context

The spec v2 accepts the risk until the upgrade to Keycloak 27.x (PA-01 B): this intent changes no behaviour of the stack, it writes the accepted risk and the published image's note in README and makes the suite hold them. The work at 27.0.0 (the realms' `cimd-allow-private-use-addresses` off, RQ-17 refusing an export that sets it on, its throwaway Keycloak 27 facts test, README's residual risks) belongs to the Keycloak upgrade's own intent (the product owner, 2026-11-01; spec, "Out of scope and residual risk"); RQ-10's tripwire makes the suite remind that intent of it.

Steps commit as `fix(0054): step <N>, <what>` (a bug intent). Docs and one light shell test only: nothing heavy runs.

## Files

| File | Change | For |
| --- | --- | --- |
| `tests/0054-docs.sh` | new: reads README for the accepted-risk note (beside the `cimd` checks of "What an application provides") and the published-image note (in "Keycloak in an application's tests"); fails while `KC_VERSION` of `keycloak-image.properties` is 27 or later and README still states the accepted risk, naming 0054 and what the upgrade's intent owes; runs that tripwire against a `mktemp` copy with `KC_VERSION=27.0.0` (must fail) and with `26.8.1` (must pass); `# covers: README.md keycloak-image.properties` | RQ-08, RQ-09, RQ-10, AC-09, AC-10, AC-12 |
| `README.md` | modified: after the `cimd` paragraph of "What an application provides" (today `README.md:221-238`), the accepted risk in plain words (RQ-09's content); in "Keycloak in an application's tests", the bullet "What the stack adds, and whether a test has it" gains the private-address note (RQ-08's content) | RQ-08, RQ-09, AC-09, AC-10 |
| `docs/intent/0054-keycloak-cimd-reaches-private-addresses/plan.md` | this plan; its `## Verification` at the end | bookkeeping |
| `docs/intent/0054-keycloak-cimd-reaches-private-addresses/intent.md`, `docs/intent/README.md` | status `planned` now, `delivered` at Stage 5 | bookkeeping |

Not changed (AC-11): `keycloak/`, `keycloak-image.properties`, `register-app.sh`, the compose files.

## Order of work

1. **Failing test**: `tests/0054-docs.sh`, its terms fixed here (e.g. for RQ-09 `accepted risk`, `unauthenticated client`, `private networks`, `dev and on the demo host`, `2026-11-01`, `Keycloak 27`; for RQ-08 `carries no refusal of private addresses`, `cimd-allow-private-use-addresses`), each read in its own section (`sed -n '/^### What an application provides/,/^### /p'`). Committed alone, `test(0054): README states no accepted risk nor the published image's note`, then frozen (`.claude/frozen-tests.local`) — skill: none — check: `bash tests/0054-docs.sh` fails on the AC-09 and AC-10 checks (the README lacks the notes) and passes the tripwire's self-checks.
2. **README notes**: the two passages of *Files*, worded from RQ-08 and RQ-09, in README's register (plain sentences, no intent jargon but the intent's number) — skill: none — check: `bash tests/0054-docs.sh` and `bash tests/run.sh --changed` (the README's other readers: `0004-registry`, `0016-no-real-provider`, `0027-docs`, `0029-description`, `0032-demo-github-only`, `0033-docs`; no facts nor stand-in test covers README) — commit `fix(0054): step 2, README states the accepted risk and the published image's note`.
3. **Verification**: `/sdlc-verify 0054` (bootstrap: one round; high risk: bugs and security passes), its evidence block into `## Verification`, commit `plan: verification of 0054`, push.
4. **Delivery**: `/sdlc-ship 0054`; tell poc-immo-pf its `CimdIT` private-address case is theirs to review (PA-04 A), as a row of its intent home or a message to its session, not a change of its code.

## Risks

- The note outlives its reason: the upgrade lands and README keeps saying the risk is accepted, or the setting is forgotten → RQ-10's tripwire fails the suite at the first `KC_VERSION` 27.x, naming what the upgrade's intent owes.
- A test that greps terms passes on words that say the wrong thing → the terms are whole phrases read inside their section, and the README passages are read at the review against RQ-08 and RQ-09, not only by the test.
- Keycloak 27.0.0's setting turns out otherwise (renamed, default on, absent) → the upgrade's intent reads it then; this plan relies on no 27.x behaviour, only on the version string.
- `KC_VERSION` read under Git Bash with a CR → read with `sed -n 's/^KC_VERSION=//p'` and the CR stripped, as `tests/0029-description.sh` does.

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| AC-09 | automated test | `tests/0054-docs.sh`, check "README's tests section says the published image carries no refusal of private addresses" |
| AC-10 | automated test | `tests/0054-docs.sh`, check "README states the accepted risk beside the cimd checks" |
| AC-11 | command | `git diff --name-only origin/main...HEAD -- keycloak/ keycloak-image.properties` prints nothing; `bash tests/0029-description.sh` passes |
| AC-12 | automated test | `tests/0054-docs.sh`, the tripwire's self-checks on a `mktemp` copy (`27.0.0` fails naming 0054, `26.8.1` passes); and step 1's run before README changes, which fails AC-09 and AC-10 (the test guards the change) |

## Deviations

<!-- filled during implementation: date — what — why — impact on files or proof -->

## Verification

<!-- the evidence block of /sdlc-verify 0054 -->
