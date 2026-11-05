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
| `.claude/protected-paths` | new: the reference's single glob over `.claude/@(settings*.json\|protected-paths\|release-commands)`, and, from deviation 3, a second line over `.githooks/**` | outcome 3, the intent's open question (decided minimal) |
| `.claude/settings.json` | new (deviation 1): the reference's wiring, `PreToolUse` only — protect-paths and freeze-tests on the edit tools, release-gate and commit-guard on `Bash\|PowerShell\|Monitor` and on `mcp__.*` | outcome 3 |
| `.githooks/pre-commit`, `pre-applypatch`, `pre-merge-commit`, `gitleaks.toml`, `secret-allowlist` | new (deviation 3): the reference's secret scan as it is, which the wired commit guard requires; committed by the Developer, the agent being refused both the edit and the commit of these paths | deviation 3 |
| `docs/intent/README.md` | modified: `- Base branch: main` becomes `- Release branch: main` and `- Delivery branch: develop`; the "One branch per intent" paragraph (line 7) and the "Bootstrap mode" paragraph (line 9) rewritten to the shared model; the status table's "never on the base branch" (line 39) names the delivery branch | outcome 1 |
| `CLAUDE.md` | modified: the verification paragraph names the delivery branch where it says "since the base branch" and `origin/main`; the repository layout gains one line on where the work lives (`bootstrap`, delivered into `develop`) | outcomes 1, 4 |
| `tests/run.sh` | modified: `--changed`'s default base becomes `origin/develop`, falling back to a local `develop`, and failing with a message that names what it tried when neither exists; its header comment (lines 9-10) follows | outcome 4 |
| `tests/0017-run.sh` | modified: the default base's checks in its throwaway repository — `git update-ref refs/remotes/origin/develop` for the preferred ref, then the local `develop` fallback, then neither | outcome 4's proof |
| `tests/0022-lanes.sh` | modified (deviation 2): its throwaway repository carries a delivery branch too, as 0017's does | outcome 4 |
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
- 2026-11-05 — **the wired commit guard requires a secret scan this repository did not have**, so no commit of the agent was possible at all: it demands an active scan (git's hooks path pointing at `.githooks/`, with an executable `pre-commit`), which the reference ships together with the hook it wires, and c4-infra had neither. The product owner chose, in the session, to add the scan here rather than to drop the guard from the wiring: the reference's five files land as they are (gitleaks 8.30.1, its rules, its allowance list, and the merge and patch entry points), git's hooks path points at them, and `.claude/protected-paths` gains the reference's line over `.githooks/**`. Division of labour, which the guards enforce: the agent may neither edit nor commit `.claude/@(settings*.json|protected-paths|release-commands)` nor `.githooks/**`, so the Developer committed them (`334249e`, the one commit of this range without the session's attribution trailer). This widens the change beyond the branch model: the intent says nothing about secrets, and it is recorded here as the product owner's scope decision.
- 2026-11-05 — **`tests/0022-lanes.sh:153` failed in the full run**: it calls `--changed` in its own throwaway repository, which had no delivery branch, so step 3's new refusal fired. Its fixture now creates `develop` and `refs/remotes/origin/develop`, as 0017's does. Impact: `tests/0022-lanes.sh` added to *Files*.

## Verification

### Verification — 55cde8c

- Verification command: `bash tests/run.sh --changed --all` → `total: 4701.2 s for 93 test(s)`, then `FAILED:` with 14 test files, 58 KO checks, exit 1 (2026-11-05), at 0fb214b
- Rerun after the fixes: bounded, by the product owner's decision in the session, to the two tests the fixes concern — `bash tests/0017-run.sh` and `bash tests/0022-lanes.sh`, each `every check passed`, exit 0, at 55cde8c. `--changed 0fb214b` would have re-selected every test, `.claude/**` and `.githooks/**` being declared by none, which no test can cover: they configure the agent, not the stack.
- Durations: lock —, bugs review 12m21s @09:14, security review —, fix round 17m57s @10:34, run 79m32s @09:14, reruns 3m40s (first verdict —) @10:51, verifier 15m22s @10:55; total 116m31s (09:14–11:10)
- Risk tier: standard (no risk rule of the intent home applies: no authentication, authorization, secret, isolation between applications, network exposure or personal data)
- Reviews: bootstrap mode: 1 round, on 7301034..0fb214b (`/Users/ch4mp/workspaces/c4-infra`); bugs: covered 7301034..0fb214b via code-review, 2 fixed / 1 answered; security: — (standard risk); quality: — (bootstrap mode drops it; the comments the diff adds were read instead, and the one that restated its code was shortened, `tests/0017-run.sh:76`)
  - Fixed: both rule files were inert, no project wiring reading them, and the MCP path carried no tool rule. Deviations 1 and 3; proven below.
  - Answered, pre-existing for this range: `env.sh:21` leaves a `.env.bak` holding the generated passwords when an interrupt or a sed failure stops it before the removal, and that name is not git-ignored, so it is committable. The line is intent 0055's uncommitted step 1 (its RQ-07): handed to 0055, not fixed here.
- Mutation checks (the verifier's; this is not a bug intent): outcome 3 — the same three gate probes, in a throwaway worktree at 7301034, give no denial at all, so the denials are this change's effect; outcome 4 — with the preference inverted, `tests/0017-run.sh` fails `0056: origin/develop is the base, not the local develop` (1 KO, exit 1), and with the pre-0056 code 3 KO. The verifier notes that the fallback check alone does not distinguish the delivery branch from the release branch in that fixture, where both point at the same commit; the refusal check does.
- Verifier: 5/5 criteria OK, 0 KO, 0 not verifiable — table below
- Not verifiable here: **the project's verification command has never passed whole for this change.** The only whole-suite run is at 0fb214b and is red. Of its 14 failing tests, 13 are verified as caused by nothing in this range (a Linux-only memory check, a missing `fr_FR.UTF-8` locale, the sample application not registered on this workstation, and Keycloak, Caddy, stand-in and Docker Desktop mount failures), and one, `tests/0022-lanes.sh`, was this change's own regression, fixed and green first-hand at 55cde8c. A whole run at 55cde8c was declined by the product owner (about 35 minutes for the same macOS failures); those failures are intent 0055's PA-02 measurement and triage.
- Files outside the plan: none. The *Files* table was completed in this commit with `.claude/settings.json`, the second line of `.claude/protected-paths`, the five `.githooks/*` files and `tests/0022-lanes.sh`, which the three deviations introduced.
- Pre-existing findings (not fixed, out of scope): `env.sh:21`'s `.env.bak` → intent 0055 (its RQ-07); the 13 macOS failures of the whole run → intent 0055's PA-02 triage; `.githooks/pre-commit`, `pre-applypatch` and `pre-merge-commit` are tracked executable scripts that no test declares and that the suite's globs (`tests/run.sh:91,100`, over `'*.sh'`) cannot see, so `CLAUDE.md`'s "a new script comes with a test that covers it" is unenforced for them → a bug intent suggested; two lines of a delivered intent's spec (`docs/intent/0017-suite-runs-every-test-every-time/spec.md:17,46`) still say "base branch", left as the historical record a delivered intent's artifacts are.

| Criterion | Result | Evidence |
| --- | --- | --- |
| Outcome 1 — the declared model is the shared one | OK | `docs/intent/README.md:23-24` holds `- Release branch: main` and `- Delivery branch: develop`; `command grep -c "base branch" docs/intent/README.md CLAUDE.md` → 0 and 0; the rewritten paragraphs at `docs/intent/README.md:7,9,40` and `CLAUDE.md:10,19` |
| Outcome 2 — the branches exist | OK | `git rev-parse origin/develop origin/bootstrap` resolves both; `git merge-base --is-ancestor origin/develop bootstrap` exits 0 |
| Outcome 3 — the gate is real here | OK | Hand-fed probes of `~/.claude/hooks/release-gate.sh`: a push of `bootstrap` onto the delivery branch → `deny` naming it, a version tag → `deny`, a plain push → no denial; the MCP path → `deny` for a pull request's merge, for a tag's ref creation and for a workflow run, no denial for a read. Live wiring: a forbidden forge command asked for its help only was blocked before running by `PreToolUse:Bash hook error: Release gate`, which only `.claude/settings.json` can produce, the account-wide settings wiring neither hook. `protect-paths.sh`, hand-fed an edit payload, refuses the four guardrail paths and allows `tests/run.sh` |
| Outcome 4 — the proof compares to what is delivered | OK | `tests/run.sh:105-111`; the five `0056:` checks of `tests/0017-run.sh`, `every check passed`, exit 0 at 55cde8c, re-run first-hand by the verifier in a clean worktree; the two mutations above show they discriminate |
| Success criterion — the undelivered work's tests | OK | `--changed`'s base resolves (`git rev-parse -q --verify origin/develop^{commit}`); the selection escalates to every test by the suite's own rule (`tests/run.sh:123-127`), which the whole run printed: `no test declares .claude/protected-paths: every test runs` |
