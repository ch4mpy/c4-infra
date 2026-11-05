# Intent: The repository still works the old branch way: no delivery branch, no bootstrap branch, and a release gate that protects nothing

- Author: Jérôme Wacongne (product owner, tech lead); drafted by the agent in the session that met the new model
- Kind: change
- Source: conversation (2026-11-05, the shared skills and hooks re-read at the start of the session: their new branch model)
- Spec needed: no (product owner, 2026-11-05: a configuration alignment that decides no observable contract)
- Status: accepted
- Opened: 2026-11-05
- Decided: 2026-11-05
- Supersedes: —
- Mode: bootstrap

## Problem

The shared skills and hooks changed the branch model: bootstrap work lives on a branch `bootstrap`, delivered into a delivery branch (`develop`) by one pull request the human merges, and in both modes the release gate denies a push, a merge or a pull landing on the release branch (`main`) or on the delivery branch, and a version tag. This repository still declares, documents and assumes the former one, and nothing of the new model exists here:

- `docs/intent/README.md` declares `- Base branch: main`, where the shared project context now reads `- Release branch:` and `- Delivery branch:` (`~/.claude/skills/sdlc-intent/readme-template.md:19-20`), and its bootstrap paragraph still says the work lands on the base branch without a PR, a branch only when another intent is in progress;
- neither branch exists: `git branch -a` lists `main` and six branches of delivered intents;
- the repository has no `.claude/` at all, so **the release gate guards nothing here**: it acts only through `.claude/release-commands` and its `release` / `delivery` lines (`~/.claude/hooks/release-gate.sh:9-11,538-561`), so a push landing on `main` passes;
- `tests/run.sh:105` compares `--changed` to `origin/main`, and `CLAUDE.md`'s verification paragraph says the same;
- 0055, planned on 2026-11-03, has its documents on `main` and its implementation not started: it would be built the old way.

Steps to reproduce: in this checkout, `git branch -a`, `ls .claude`, and `grep "Base branch" docs/intent/README.md`. Expected, per the shared skills: a `bootstrap` branch, a `develop` branch, a `.claude/release-commands` naming both, and a project context declaring the release and delivery branches. Observed: `main` alone, no `.claude/`, `- Base branch: main`.

What it costs: every change of this repository lands on the release branch with no gate between the work and `main`; the skills' assumptions and the repository's declaration diverge, so each session has to be told the model by hand, as this one was; and a release has no delivery branch to come from.

## Proposed outcome

- The declared model is the shared one: the project context names the release branch and the delivery branch, and its bootstrap paragraph describes work on `bootstrap`, delivered into the delivery branch by a pull request the human merges, a parallel intent's branch being merged into `bootstrap` locally.
- The branches exist: `develop` as the delivery branch, `bootstrap` as the work branch.
- The release gate is real here: `.claude/release-commands` names the release and the delivery branch and denies what `CLAUDE.md` already calls the human's — merging or approving a pull request, a release, a version tag, and starting the demo workflow or pushing an image, which publish the demo's images.
- A change's proof compares to what is delivered: `tests/run.sh --changed` defaults to the delivery branch.
- No document of the repository names a "base branch" any more.

Success criterion: on `bootstrap`, a simple push passes, while a push, a merge or a pull landing on `main` or on the delivery branch, and a version tag, are denied with their reason; `bash tests/run.sh --changed` selects the tests of the undelivered work; and `docs/intent/README.md`, `CLAUDE.md` and `tests/run.sh` name the delivery branch where they named `main`.

## Affected users and systems

- **Developer** (the branch they work on, and the proof they run). No new persona or module.
- The intent home (`docs/intent/README.md`), the verification (`tests/run.sh`, `CLAUDE.md`), and a new `.claude/` holding the gate's rules.

## Constraints

- **The product owner's decisions of 2026-11-05**: this intent carries no spec; `tests/run.sh --changed` defaults to `origin/develop`; `.claude/release-commands` carries the two branch lines **and** the denials of the release commands.
- **The delivery branch's creation and its first push are the human's**: the gate denies them to the agent, and ordering the work so that a push passes before the gate's file exists is the circumvention the rules forbid ("never to make a push pass").
- 0055 keeps its `Mode: bootstrap` field and is implemented on `bootstrap` once this change lands; the documents it already has on `main` travel into the delivery branch with it.
- `.github/workflows/deploy-demo.yml` triggers on a push to `main` and stays as it is: `main` remains the release branch, and the demo still deploys from it.
- `docs/intent/HANDOVER.md` recounts merges into `main` as they happened: it is a historical record, not a declaration of the model.

## Open questions

- Should a `.claude/protected-paths` come with the gate's file, so that `.claude/release-commands` is itself out of the agent's reach (the shared skills assume it is: `sdlc-intent` §11 says "the Developer adds `delivery develop` (the file is protected)")? Without it, the agent can edit the very file that limits it. — product owner, at the plan.
