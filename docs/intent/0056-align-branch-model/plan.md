# Plan: the repository still works the old branch way: no delivery branch, no bootstrap branch, and a release gate that protects nothing

- Intent: [0056](intent.md) (no spec: product owner, 2026-11-05)
- Status: approved
- Branch: `bootstrap`
- Approved: 2026-11-05, Jérôme Wacongne (engineer, product owner and tech lead, recorded once; the gate being ExitPlanMode in this session)

## Context

The shared skills and hooks changed the branch model: bootstrap work lives on `bootstrap`, delivered into a delivery branch (`develop`) by one pull request the human merges, and in both modes the release gate denies a push, a merge or a pull landing on the release or the delivery branch, and a version tag. c4-infra still declared the former model (`- Base branch: main`), had neither branch, and had no `.claude/` at all — so the gate guarded nothing here and a push to `main` passed. The Developer created `develop` from `7301034` on 2026-11-05 (the gate denies that push to the agent); `bootstrap` was cut from the same commit and carries intent 0056. This plan brings the declaration, the gate and the proof's base in line, so that no session has to be told the model by hand again.

Product owner's decisions of 2026-11-05: no spec; `--changed` defaults to `origin/develop`; `.claude/release-commands` carries the two branch lines **and** the release denials; `.claude/protected-paths` is minimal — the two `.claude/` files protect each other, nothing else.

## Files

| File | Change | For |
| --- | --- | --- |
| `.claude/release-commands` | new: `release main`, `delivery develop`, and the denials of what `CLAUDE.md` already calls the human's — merging or approving a pull request, `gh release`, a version tag (CLI and API), and `gh workflow run` / `run rerun` or an image push, which publish the demo's images | outcome 3 |
| `.claude/protected-paths` | new: `never .claude/release-commands` and `never .claude/protected-paths`, each with its reason | outcome 3, the intent's open question (decided minimal) |
| `docs/intent/README.md` | modified: `- Base branch: main` becomes `- Release branch: main` and `- Delivery branch: develop`; the "One branch per intent" paragraph (line 7) and the "Bootstrap mode" paragraph (line 9) rewritten to the shared model; the status table's "never on the base branch" (line 39) names the delivery branch | outcome 1 |
| `CLAUDE.md` | modified: the verification paragraph names the delivery branch where it says "since the base branch" and `origin/main`; the repository layout gains one line on where the work lives (`bootstrap`, delivered into `develop`) | outcomes 1, 4 |
| `tests/run.sh` | modified: `--changed`'s default base becomes `origin/develop`, falling back to a local `develop`, and failing with a message that names what it tried when neither exists; its header comment (lines 9-10) follows | outcome 4 |
| `tests/0017-run.sh` | modified: the default base's checks in its throwaway repository — `git update-ref refs/remotes/origin/develop` for the preferred ref, then the local `develop` fallback, then neither | outcome 4's proof |
| `docs/intent/0056-align-branch-model/plan.md` | new: this plan, then its `## Verification` section | bookkeeping |
| `docs/intent/0056-align-branch-model/intent.md` | modified: status `planned` | bookkeeping |
| `docs/intent/README.md` | modified: the index row's status | bookkeeping |

## Order of work

Estimates: `step-durations.sh` answers `no measured step` on this repository, so every estimate below is **not measured**, by judgement, with the machine time named apart.

1. **The gate's files** — skill: none — (code, not measured; machine 2 min) — check: the hook's verdict on three probes, below.
   Write `.claude/release-commands` first, prove it, and only then `.claude/protected-paths`: from that second file on, the agent may no longer edit the first one, so a mistake in it would be the Developer's to fix.
   The proof **executes nothing**: `release-gate.sh` is a `PreToolUse` hook that reads a JSON payload on stdin (`.tool_name`, `.tool_input.command`) and prints a `permissionDecision` (`~/.claude/hooks/release-gate.sh:99,118`). Three probes, run from the repository:
   - `{"tool_name":"Bash","tool_input":{"command":"git push origin bootstrap:develop"}}` → `deny`, its reason naming the delivery branch;
   - `{"tool_name":"Bash","tool_input":{"command":"git tag v9.9.9"}}` → `deny`, a version tag being the human's;
   - `{"tool_name":"Bash","tool_input":{"command":"git push"}}` → no denial (a simple push of `bootstrap` passes).
   If a probe needs a directory field, take its name from the hook's header rather than guessing.

2. **The declared model** — skill: none — (docs, not measured; machine 1 min) — check: `command grep -n "base branch" docs/intent/README.md CLAUDE.md` prints nothing, and `command grep -n "Release branch\|Delivery branch" docs/intent/README.md` prints both lines.
   The bootstrap paragraph says what the shared skill says: the work lives on `bootstrap`, a parallel intent's branch is cut from it and merged back into it locally, `bootstrap` reaches the delivery branch by one pull request the human merges, and the release gate denies a push, a merge or a pull landing on the release or the delivery branch, and a version tag.

3. **The proof's base** — skill: none — (code, not measured; machine 2 min) — check: `bash tests/0017-run.sh`.

Closing, not a code step: `/sdlc-verify 0056` (bootstrap mode: one round, the bugs pass only, no simplify pass, and no security pass — this change touches no authentication, authorization, secret, isolation or exposure), its evidence block pasted into `plan.md`'s `## Verification`, commit `plan: verification of 0056`, then the diff checked against this plan on `origin/develop...HEAD` and pushed.

## Risks

- **The verification is a full run**: `tests/run.sh` changes, and the suite's own rule makes a change to it run every test, so `bash tests/run.sh --changed --all` is the whole suite, about half an hour with two stand-in lanes. It cannot be shortened without weakening the proof. It does not serve 0055's PA-02 run, whose code is not in yet.
- A denial could catch a command the work legitimately needs → the denials are copied from what `CLAUDE.md` already calls the human's, and an over-reach shows as a denial naming its reason; from step 1 on, amending that file is the Developer's.
- Protecting `release-commands` in the same step that writes it would lock a mistake in → the step writes and proves it before writing `protected-paths`, and reports both files' content.
- `tests/run.sh`'s new default fails where no `develop` exists (an older clone) → intended, and the message names the refs it tried instead of silently comparing to `main`.
- `.github/workflows/deploy-demo.yml` triggers on a push to `main` and is untouched: `main` stays the release branch, and the demo still deploys from it.

## Proof

| Criterion (intent 0056) | How | Test, command or check |
| --- | --- | --- |
| Outcome 1 — the declared model is the shared one | command | `command grep -n "Release branch\|Delivery branch" docs/intent/README.md` prints both; `command grep -c "base branch" docs/intent/README.md CLAUDE.md` prints 0 for each |
| Outcome 2 — the branches exist | command | `git rev-parse origin/develop origin/bootstrap` resolves both, and `git merge-base --is-ancestor origin/develop bootstrap` holds |
| Outcome 3 — the gate is real here | command | step 1's three hook probes: `deny` naming the delivery branch, `deny` on a version tag, no denial on a simple push |
| Outcome 4 — the proof compares to what is delivered | automated test | `bash tests/0017-run.sh`, its three default-base checks (`origin/develop`, the local `develop`, neither) |
| Success criterion — the undelivered work's tests | command | `bash tests/run.sh --changed` on `bootstrap` selects the tests the undelivered commits concern, and the verification's full run's summary line |

## Deviations

- 2026-11-05 — **the gate's files were inert, and its MCP path uncovered** (the review's two Important findings). `.claude/release-commands` and `.claude/protected-paths` are read by nothing on their own: no `.claude/settings.json` wired `release-gate.sh` and `protect-paths.sh` for this project (only `shell-guard.sh` is wired account-wide), so a push landing on the delivery branch would have run; and the file carried no `deny-tool` rule, so a forge's MCP tool (`mcp__github__merge_pull_request`, `mcp__gitlab__accept_merge_request`, `create_ref ref=refs/tags/…`, `run_workflow`) passed while its shell equivalent was denied. Step 1's proof could catch neither, because it fed the hook a payload by hand instead of exercising it. Fixed by writing `.claude/settings.json` with the reference's wiring (`PreToolUse` only: protect-paths and freeze-tests on the edit tools, release-gate and commit-guard on `Bash|PowerShell|Monitor` and on `mcp__.*`), appending the reference's 34 `deny-tool` / `command-tool` rules, and replacing the two `never` lines with the reference's single glob, which protects `settings.json` too. Those three paths are the ones this change declares protected: the product owner authorised the edit in this session. Impact: `.claude/settings.json` added to *Files*, and outcome 3's proof gains a live probe — the pull-request merge command, asked for its help only, denied by the hook in this session — beside the hand-fed ones.
- 2026-11-05 — **`tests/0022-lanes.sh:153` failed in the full run**: it calls `--changed` in its own throwaway repository, which had no delivery branch, so step 3's new refusal fired. Its fixture now creates `develop` and `refs/remotes/origin/develop`, as 0017's does. Impact: `tests/0022-lanes.sh` added to *Files*.

## Verification

<!-- filled at the end of the implementation: sdlc-verify's evidence block, as is -->
