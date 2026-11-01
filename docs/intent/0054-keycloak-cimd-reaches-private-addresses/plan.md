# Plan: Keycloak fetches a client's metadata document from a private address when a trusted domain resolves to one

- Spec: [v4](spec.md) (approved 2026-11-01: PA-01 B, PA-02 A, PA-03 B, PA-04 A, PA-05 A moot; v4, the review round's decisions)
- Status: approved
- Branch: `0054-keycloak-cimd-reaches-private-addresses`
- Approved: 2026-11-01, Jérôme Wacongne (engineer and tech lead, recorded once; the plan's one choice, where the 27.x work goes, decided by him and relayed by the coordinating session)

## Context

The spec v3 accepts the risk until the upgrade to Keycloak 27.x (PA-01 B): this intent changes no behaviour of the stack, it writes the accepted risk and the published image's note in README and makes the suite hold them. The work at 27.0.0 (the realms' `cimd-allow-private-use-addresses` off, RQ-17 refusing an export that sets it on, its throwaway Keycloak 27 facts test, README's residual risks) belongs to the Keycloak upgrade's own intent, to be taken up end of January or early February 2027, Keycloak 27.0's release being planned for 29 January 2027 (the product owner, 2026-11-01; spec, "Out of scope and residual risk"); RQ-10's tripwire makes the suite remind that intent of it.

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

1. **Failing test**: `tests/0054-docs.sh`, its terms fixed here (e.g. for RQ-09 `accepted risk`, `unauthenticated client`, `private networks`, `dev and on the demo host`, `2026-11-01`, `Keycloak 27.0`, `29 January 2027`; for RQ-08 `carries no refusal of private addresses`, `cimd-allow-private-use-addresses`), each read in its own section (`sed -n '/^### What an application provides/,/^### /p'`). Committed alone, `test(0054): README states no accepted risk nor the published image's note`, then frozen (`.claude/frozen-tests.local`) — skill: none — check: `bash tests/0054-docs.sh` fails on the AC-09 and AC-10 checks (the README lacks the notes) and passes the tripwire's self-checks.
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

- 2026-11-01 — step 1's terms: beyond the plan's examples, `trusted domain` and `end of January or early February 2027` for RQ-09, `proves nothing of the stack` for RQ-08 — AC-09 and AC-10 name them — none on files or proof.
- 2026-11-01 — the review round (bootstrap: one round): the product owner lifts the freeze on `tests/0054-docs.sh` (decision 1) — spec v4 bounds AC-09 and AC-10 to Keycloak below 27, and the review's details asked a stronger test — `tests/0054-docs.sh` rewritten: AC-09 and AC-10 skipped from 27, RQ-10 anchored on the marker `accepted risk (intent 0054)` anywhere in README, AC-10 read in the `cimd` checks' item only with every term AC-10 lists, the refusal checked for what the upgrade owes, AC-12 on a copy without the note (passes) then with the marker inserted (refused), and README as it is at 26.8.1; README's note reworded (decision 2), its nested list kept tight, and the isolation section points to it. Proof unchanged in shape: the same test.

## Verification

### Verification — 76601d0

Bootstrap mode (intent home's `Mode` line): no PR, no stage label, gates decided in this session; the release gate does not hold pushes to `main`.

- Verification command: `bash tests/run.sh --changed origin/main --all` (from the worktree, `TMPDIR` under `/home`, `C4_DOCKER_REAP=labelled`) at 0f2ae33 → `FAILED: tests/0004-registry.sh` (the worktree has no `.env`: `INFRA_ENV ''`, environment); the first attempt stopped at the preflight, host memory 5.4 GiB under its floor of 6 (2026-11-01)
- Rerun after the fixes: `bash tests/run.sh --changed origin/main --all` from the main checkout detached at 76601d0 → `verification passed (--changed: 9 of 93 tests)`
- Durations: not computed — the session's phases file refused its second `end run` ("run ends without a start", the improvement log's P-58); run about 1 min, bugs review 7m28s, security review 1m36s, fix round 3m43s, rerun 8 s, verifier 2m08s
- Risk tier: high (authentication; what a host exposes to the network)
- Reviews: bootstrap mode: 1 round, on f9d7f1e..0f2ae33 (`/home/jerome/workspaces/c4-infra-0054`); bugs (xhigh): covered f9d7f1e..0f2ae33, 1 Important fixed (AC-10 against RQ-10 after the upgrade: AC-09/AC-10 bounded to Keycloak < 27, the PO lifting the test's freeze), 9 details: 7 fixed (README wording, the test's marker, terms, message and self-checks), 2 answered (the shared docs-test helper and 0004's `.env`: out of scope); security: covered f9d7f1e..0f2ae33, 1 Important fixed (the free precaution: exact names or zones the realm's owner controls, never wildcard-DNS or shared-hosting suffixes), 2 details fixed (the reach exactly: HTTPS, a blind probe; the residual risk after 27.0)
  - Pre-existing: `register-app.sh`'s RQ-17 accepts wildcard-DNS and shared-hosting suffixes as trusted domains → `~/.claude`'s improvement log P-66, for the PO or the Keycloak 27 upgrade's intent
- Mutation check: HEAD's `tests/0054-docs.sh` against the README of f9d7f1e: `KO - (AC-09)`, `KO - (AC-10)`, `2 check(s) failed` (exit 1); with `KC_VERSION=27.0.0` and the note kept: `KO - (RQ-10) … 0054: Keycloak's major version is 27 and README still holds 'accepted risk (intent 0054)' … owes …`
- Verifier: 4/4 criteria OK (AC-09, AC-10, AC-11, AC-12; RQ-10 through AC-12), 0 KO; its details (README wording on `cimd-allow-http-scheme`, AMQP not HTTP, the AC-09 setting-name check) left for the upgrade's intent, which rewrites those notes
- Not verifiable here: none
- Files outside the plan: none
- Pre-existing findings: P-66 above

| Criterion | Result | Evidence |
| --- | --- | --- |
| AC-09 | OK | `ok - (AC-09) README's tests section says the published image carries no refusal of private addresses`; skipped at 27 |
| AC-10 | OK | `ok - (AC-10) README states the accepted risk in the cimd checks' item` (20 terms) |
| AC-11 | OK | `git diff --name-only origin/main...HEAD -- keycloak/ keycloak-image.properties` empty; 0029 `every check passed` |
| AC-12 | OK | the four `ok - (AC-12)` lines; live check at 27.0.0 refused naming 0054 and what is owed |

<!-- the evidence block of /sdlc-verify 0054 -->

Step 1, before README changes (AC-12: the test guards the change), `bash tests/0054-docs.sh`, exit 1:

```
KO - (AC-09) README's tests section says the published image carries no refusal of private addresses
     'Keycloak in an application's tests' doesn't name 'carries no refusal of private addresses' 'cimd-allow-private-use-addresses' 'proves nothing of the stack'
KO - (AC-10) README states the accepted risk beside the cimd checks
     'What an application provides' doesn't name 'accepted risk' 'trusted domain' 'private networks' 'dev and on the demo host' '2026-11-01' 'Keycloak 27.0' 'end of January or early February 2027' '29 January 2027'
ok - (RQ-10) README states no accepted risk once Keycloak is 27 or later
ok - (AC-12) a copy at 27.0.0 still stating the risk is refused, naming 0054
ok - (AC-12) a copy at 26.8.1 stating the risk passes
2 check(s) failed
```
