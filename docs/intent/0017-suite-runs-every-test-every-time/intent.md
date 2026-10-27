# Intent: The verification runs every test every time, and says nothing of where its time goes

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: change
- Source: conversation (verification of 0013, 2026-10-27)
- Spec needed: yes
- Status: accepted
- Opened: 2026-10-27
- Decided: 2026-10-27
- Supersedes: —

## Problem

`bash tests/run.sh` runs every test of `tests/`, and `--all` adds the stand-in demo host's. On 2026-10-27, `--all` took 32 minutes for its first 28 tests out of 40, before the stand-in ones. Four intents are planned (0013, 0011, 0015, 0016), and each plan runs it at every verification and again after every fix round, so the suite sets the pace of delivery.

- Nothing says which test takes the time: the output prints no duration.
- A plan step's check names its tests by hand. Nothing gives the tests a changed file concerns, so it's either a guess or the whole suite.
- The facts tests (`tests/*-facts.sh`) measure Keycloak's and Caddy's behaviour on throwaway containers at every run, though that behaviour only changes with their versions.
- Two runs on the same Docker spoil each other: during 0013's step 8 (2026-10-24), an image was rebuilt and pruned under the running proxy by another session, and the run had to be done again (0013's plan, *Deviations*). Nothing warns that the dev stack is already in use.

## Proposed outcome

A Developer verifying a change can see where the suite's time goes, run only the tests a change concerns for an intermediate check, and is told when another run already uses the dev stack, instead of getting results spoiled by it. The full run stays the proof a change is verified with, and never runs fewer tests than today.

Success criterion: the duration of each test is printed; an intermediate check of a change to one script runs only the tests that change concerns; two runs started at the same time on one workstation don't both use the dev stack.

## Affected users and systems

- Developer.
- Verification (`tests/run.sh`, `tests/lib/`, the facts tests): *not declared in the project context's modules*. CLAUDE.md's "Verification".

## Constraints

- The full run (`--all`) keeps every test it runs today, and remains what `sdlc-verify` runs before a change is reviewed: nothing here makes a test optional for that proof.
- It runs where the suite runs today: Git Bash on Windows and the demo host's Linux, with the dev stack's Docker.
- No test is weakened or removed to save time.

## Open questions

- The target: how long may an intermediate check of a one-script change take, and the full run? — product owner, once durations are measured
- When do the facts tests run, if not at every run: with `--all` only, when a version of Keycloak or Caddy changes, or both? — tech lead
- How a changed file maps to its tests (by intent number, by a list kept with each test, by what the test sources or runs). — the spec
- *Suggested solution* (conversation, 2026-10-27): a duration per test in `run.sh`'s output; a `--changed` option choosing the tests from `git diff`; a lock held by `run.sh` on the dev stack for the run's length; the facts tests run with `--all` or on a version change. — the spec
