# Plan: The registry test requires exactly four applications, so registering a new one fails the verification

- Spec: none, the [intent](intent.md) (bug, spec needed: no)
- Status: approved
- Branch: 0018-registry-test-pins-four-entries
- Approved: 2026-10-27, Jérôme Wacongne (engineer; standard risk)

## Starting point

`registry.txt`'s header tells a new application to add its line before it registers. `tests/0004-registry.sh` checks the real registry and requires exactly four entries (`check "entries: four entries" test "$(entries | wc -l)" -eq 4`, line 82). Since `0cf541c` (immo, block 5), `main` fails that check, so `bash tests/run.sh` is red on `main`, and every intent after it (0017, 0011, 0015, 0016) would start its verification red. Outcome: a valid entry added as the header says leaves the verification green. The test keeps checking that the real registry passes `registry.sh check` and still holds the four applications of 0004, each with one entry of seven fields.

Facts read:
- the `registry` part of `tests/0004-registry.sh` (`entries`, `has_entry`) reads `registry.txt` relative to the repository root (`cd "$(dirname "$0")/.."`). `registry.sh` reads `registry.txt` and `.env` next to itself. A missing `.env` reads as empty, and the part passes in a scratch copy without one: measured, only the `scripts` part needs `.env`;
- the part also asserts that `verif` is **not** in the real registry (`entry verif` exits 1, `upstream verif …` exits 1), so the added entry must not be named `verif`;
- no other test counts the registry's entries: `0006-registration-without-bootstrap-password.sh` and `0007-dev.sh` copy `registry.txt` as data, and the rest use fixtures;
- the scratch-copy idiom already exists: `cp … "$work/"` in `tests/0006-registration-without-bootstrap-password.sh:24`, `tests/0007-dev.sh:194`. Assertions use `check` and `finish` (`tests/lib/assert.sh`).

## Files

| File | Change | For |
| --- | --- | --- |
| `tests/0018-registry-grows.sh` | new: copies `registry.sh`, `registry.txt`, `tests/0004-registry.sh`, `tests/lib/` and `tests/fixtures/0004/` into a scratch directory, appends one valid entry numbered by `bash registry.sh next` (`<n> extra extra - - extra.dev.localhost extra.c4-soft.com`), then checks that `registry.sh check` passes there and that `tests/0004-registry.sh registry` run there passes | success criterion "one more valid line" |
| `tests/0004-registry.sh` | modified: the `entries: four entries` check removed; the header's "the four entries (AC-06)" becomes "the four applications' entries (AC-06)". No other line changes | success criterion "main with immo's line", "no other check changes" |
| `docs/intent/0018-registry-test-pins-four-entries/plan.md` | new: this plan, then its `## Verification` | bookkeeping |
| `docs/intent/0018-registry-test-pins-four-entries/intent.md` | status `planned` (here), `delivered` (`sdlc-ship`) | bookkeeping |
| `docs/intent/README.md` | 0018's index row follows the status | bookkeeping |

## Order of work

0. **Setup**: on `0018-registry-test-pins-four-entries` (`main` at `b70f166` plus the intent), `bash up.sh` so that the dev stack runs `main`'s code, 0013 included. **The dev Keycloak goes to 26.8.1 for good, and the stack poc-immo-pf uses restarts.** — skill: none — check: `bash tests/run.sh` → its `FAILED:` list holds `tests/0004-registry.sh` alone, failing on `entries: four entries` alone (the baseline on this workstation; any other failure is a deviation, recorded before step 1).
1. **Failing test**: `tests/0018-registry-grows.sh`. — skill: none — check: `bash tests/0018-registry-grows.sh` exits 1, its one `KO` being the `tests/0004-registry.sh` check, whose output shows `KO - entries: four entries` and no other `KO`. Commit `test(0018): one more registry entry fails tests/0004-registry.sh`, then freeze it (`.claude/frozen-tests.local`).
2. **Fix**: `tests/0004-registry.sh` as in *Files*. — skill: none — check: `bash tests/0018-registry-grows.sh && bash tests/0004-registry.sh` → `every check passed` twice; `git diff HEAD~1 -- tests/0004-registry.sh` shows the count line and the header word only. Commit `fix(0018): tests/0004-registry.sh no longer pins the number of entries`.
3. **Verification**: `bash tests/run.sh` → `verification passed`; mutation check: `tests/0004-registry.sh` of `main`, put back in the working tree → `bash tests/0018-registry-grows.sh` exits 1 on `entries: four entries`, then restored; `/sdlc-verify 0018` (bootstrap mode: one round, the bugs pass; standard risk, so no security pass); its evidence block goes into `## Verification`, commit `plan: verification of 0018`, push. Next: `/sdlc-ship 0018`.

## Risks

- Another test fails on this workstation (immo's line, the new machine, the stack at 26.8.1) → step 0's baseline shows it before any change; recorded as a deviation, and as a bug intent when it is not 0018's.
- `bash up.sh` upgrades the dev Keycloak's database to 26.8.1 with no way back, and restarts the stack poc-immo-pf uses → said at approval (this plan); `main` is at 26.8.1 since 0013 anyway.
- The scratch copy lacks a file the `registry` part needs, and the test fails for the wrong reason → step 1 requires `entries: four entries` to be the only `KO` of 0004's output.
- Dropping a check weakens 0004 → only the count goes. `check passes`, the four `has_entry`, Tickee's line and every `entry`, `next` and `upstream` check stay, and `tests/0018-registry-grows.sh` keeps the growth case covered.
- 0017 adds a `# covers:` line to every test → 0017's step 0 (after merging `main`) gives `tests/0018-registry-grows.sh` one (`registry.txt`, `registry.sh`, `tests/0004-registry.sh`). 0016 also edits `tests/0004-registry.sh`, on other lines.
- The delivery push to `main` changes `tests/`, which `deploy-demo.yml` doesn't ignore, so the demo host is redeployed with unchanged images → expected, followed by `sdlc-ship`.

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| `main` with immo's line passes | automated test | `bash tests/0004-registry.sh` → `every check passed` (step 2) and within `bash tests/run.sh` (step 3) |
| One more valid line passes | automated test + mutation check | `bash tests/0018-registry-grows.sh` → `every check passed`; with `main`'s `tests/0004-registry.sh` → exit 1 on `entries: four entries` (step 3) |
| The real registry still passes `check` and holds the four applications of 0004 | review + automated test | `git diff main -- tests/0004-registry.sh`: the count line and one header word only; `has_entry` for turu, hururaa, tickee, faito passes |
| The full verification is green | command | `bash tests/run.sh` → `verification passed` |

## Deviations

<!-- filled during implementation: date — what — why — impact on files or proof -->

- 2026-10-27 — step 0's baseline (`bash tests/run.sh`, 957 s, stack at 26.8.1): 11 tests fail, not one. (1) Docker Desktop on this workstation doesn't share `/tmp`: the five tests that bind-mount their `mktemp` directory (`0003-caddy-config`, `0003-demo-edge`, `0007-dev`, `0007-listeners`, `0009-master-import-facts`) pass with `TMPDIR=$HOME/.cache/c4-infra-tests`, which the verification uses from here on. (2) `../faito` is not Faito's repository here (a repository without a commit) and realm `faito` isn't in the dev Keycloak: `0003-dev-routes`, `0005-themes`, `0006-account`, `0006-keycloak-facts` and `0006-registration-without-bootstrap-password` fail on that alone; none of them covers a file 0018 changes. (3) `0004-registry.sh`: the bug, `entries: four entries` its only `KO`. Impact on proof: "the full verification is green" needs Faito on the workstation (product owner's decision).
- 2026-10-27 — step 2: "applications'" lengthened the header's line, so its next two comment lines are rewrapped ("(AC-03), `next`" moved down a line); no check other than the count changes. No impact on proof.
- 2026-10-27 — `sdlc-verify`'s bug review: `tests/0018-registry-grows.sh` glued its entry to a last line without a new line, which `registry.sh check` accepts (measured: then `13 columns, 7 expected`), and an exported `REGISTRY_FILE` turned its two calls away from the scratch registry. Unfrozen with the product owner's go and changed: the entry on a line of its own, `REGISTRY_FILE` unset, the entry inlined, a shorter header; frozen again. Impact on proof: the mutation check runs again with the changed test, at `74c4796`.

## Verification

### Verification — e49e53c

- Verification command: `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh` → `verification passed` (2026-10-27, 20:06–20:28 UTC, 1310 s; dev stack at 26.8.1, Faito registered from `../faito`)
- Risk tier: standard (tests only; no risk rule applies)
- Reviews: bootstrap mode: 1 round; bugs (`code-review`, high): 10 findings, 4 fixed in e49e53c, 6 answered; no security pass (standard risk), no quality pass (bootstrap mode)
  - fixed: the added entry glued to a last line without a new line, which `registry.sh check` accepts (measured: `13 columns, 7 expected`); an exported `REGISTRY_FILE` turning the test's two calls away; the single-use function; the long header (tests/0018-registry-grows.sh)
  - answered, out of scope: 0004 also pins other live registry data (Tickee's line, `entry faito`'s fields and Faito's ports), so editing an existing line would break it the same way; the intent keeps every other check → bug intent suggested, 0004's contract checks on a fixture (tests/0004-registry.sh:84)
  - answered, the project's idiom: the scratch copy's `cp` and `next` aren't checked one by one, as in `tests/0006-registration-without-bootstrap-password.sh:24`; 0004's output names what is missing, and a failing `next` gives a 6-column line `check` refuses (tests/0018-registry-grows.sh:14)
  - answered, by design: the count also kept a stray test entry out of the real registry, and kept every new application out with it (tests/0004-registry.sh:82); the scratch copy has no `.env`, since the test is about growth, and the real 0004 run checks the RabbitMQ administrator rule (tests/0018-registry-grows.sh:14)
  - answered, fixed at the source outside this branch: `TMPDIR` for Docker Desktop, and Faito, in `CLAUDE.md`'s Verification on `main` (b556bc3)
- Mutation check (bug): e49e53c's `tests/0018-registry-grows.sh` in a worktree at 74c4796 (before the fix) → exit 1, `KO - entries: four entries` the only `KO` in 0004's output, `1 check(s) failed`; at e49e53c with `registry.txt` lacking its final new line → `every check passed`; with `REGISTRY_FILE` exported to a fixture → `every check passed`
- Verifier: 3/4 criteria OK, 0 KO; the fourth (the full suite) not rerun by it, proved by the verification command above
  - detail it raised, not fixed (one fix round): the 0018 test doesn't assert that the scratch registry holds the added entry; the mutation check shows the entry reaches 0004 at this commit
- Not verifiable here: none
- Files outside the plan: none
- Pre-existing findings (not fixed, out of scope): 0004's other pins on live registry data (above) → bug intent suggested

| Criterion | Result | Evidence |
| --- | --- | --- |
| `main` with immo's line passes | OK | `bash tests/0004-registry.sh` (registry, scripts, docs) → 87 `ok`, 0 `KO`, `every check passed` (verifier); within the verification command |
| One more valid line passes | OK | `bash tests/0018-registry-grows.sh` → `every check passed`; mutation check above |
| The real registry still passes `check` and holds the four applications of 0004 | OK | `git diff main...HEAD -- tests/0004-registry.sh`: the count check removed and the header rewrapped (*Deviations*); `ok - entries: check passes on registry.txt`, `ok - entries: {turu,hururaa,tickee,faito} has one entry of seven fields` |
| The full verification is green | OK | `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh` → `verification passed` on e49e53c |
