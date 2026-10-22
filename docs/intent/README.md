# Intents

Stage 1 (Plan) of the [AI-native SDLC](https://claude.com/resources/articles/the-ai-native-sdlc-playbook): every change starts as an **intent**, a short statement of a need that the product owner accepts or rejects before anyone specifies, plans or codes it.

One folder per change, numbered: `NNNN-<slug>/` holds `intent.md`, then `spec.md` (Stage 2) and `plan.md` (Stage 3). An accepted intent is never rewritten: a changed need is a new intent that supersedes it.

**One branch per intent.** A change lives on a single branch, `NNNN-<slug>`, with a single draft PR, from its draft to its delivery: intent, spec, plan and code are committed on it, and it reaches the base branch once, merged by a human just before deployment. Each gate leaves a status commit, a PR comment naming the decider, and moves the PR's label (`stage:intent` → `stage:spec` → `stage:plan` → `stage:build` → `stage:review`). The index below lists what reached the base branch; **work in progress is the open PRs with a `stage:*` label**.

## Project context

<!-- Read by the sdlc-* skills. Keep it short and up to date. -->

- Language: English
- Personas and roles:
  - **Developer**: runs one or more applications on a workstation, on top of the dev stack;
  - **Demo operator**: sets up and runs the demo host (VPS, DNS, GitHub environment and secrets);
  - **Application**: a project that registers with the stack (Faito, Hurura'a, Tickee, Turu…), its deployment scripts and workflows;
  - **Demo visitor**: anyone using an application on the public demo host.
- Modules / systems: dev stack (`compose.yml`, `nginx/`), demo stack (`demo/`, Caddy), registration (`register-app.sh`, `export-realm.sh`, `new-realm-ids.sh`), certificates (`certs/`), port registry (`README.md`), deployment workflow (`.github/workflows/`)
- Standing constraints: the design section of [README.md](../../README.md); the decision that created this stack, [Faito's decision 0001](https://github.com/ch4mpy/faito/blob/main/docs/decisions/0001-infra-partagee.md) (one origin per application, Keycloak on PostgreSQL, `infra.c4-soft.com`)
- Base branch: main
- Product owner(s): Jérôme Wacongne (also tech lead)
- Intent template: [_intent-template.md](_intent-template.md)
- Policies: none yet
- Tech lead: Jérôme Wacongne
- Spec template: [_spec-template.md](_spec-template.md)
- Risk rules: a spec is high-risk if it touches authentication, authorization or secrets, the isolation between applications, what a host exposes to the network, or personal data; standard otherwise
- Status vocabulary:

  | Key | Label | Set by |
  | --- | --- | --- |
  | proposed | proposed | Stage 1, when the intent's PR is opened |
  | accepted | accepted | the product owner (status commit, PR comment, label `stage:spec` or `stage:plan`) |
  | rejected | rejected | the product owner (PR closed, never on the base branch) |
  | specified | specified | Stage 2, once `spec.md` is approved |
  | planned | planned | Stage 3, once `plan.md` is approved |
  | delivered | delivered | Stage 5, just before the merge that deploys it |
  | abandoned | abandoned | superseded by another intent, or dropped |

## How to propose and decide

- **Propose**: open an issue with the intent form, or run `/sdlc-intent draft <idea>` (or `draft #<issue>`). The intent arrives as a draft PR labelled `stage:intent`, on its own branch `NNNN-<slug>`.
- **Decide** (product owner): `/sdlc-intent accept <NNNN>` records the acceptance on the branch (nothing is merged); `/sdlc-intent reject <NNNN> <reason>` closes the PR with the reason.
- **Measure**: `/sdlc-intent stats`.

## Index

| No. | Intent | Kind | Status | Opened | Decided |
| --- | --- | --- | --- | --- | --- |
| 0005 | [A theme change restarts the Keycloak every application uses](0005-theme-change-restarts-keycloak/intent.md) | change | proposed | 2026-10-21 | — |
