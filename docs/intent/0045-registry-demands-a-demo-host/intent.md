# Intent: The registry demands a demo host of an application the demo host never deploys

- Author: Jérôme Wacongne (product owner, tech lead); drafted by the agent from the reading of poc-immo-pf of 2026-10-30
- Kind: change
- Source: conversation (2026-10-30: `registry.txt` names `immo.c4-soft.com`, while the README says immo isn't deployed by this stack)
- Spec needed: yes
- Status: planned
- Opened: 2026-10-30
- Decided: 2026-10-30
- Supersedes: —
- Mode: bootstrap

## Problem

Every line of `registry.txt` must name a demo host (`registry.sh check` refuses `-` there). immo, a GitLab project deployed on Kubernetes by its own pipeline (the product owner, 2026-10-28; README, "Demo host"), therefore reserves `immo.c4-soft.com`, a host the demo host will never serve: the registry says the opposite of the README, and an application that will never be deployed there can't say so.

## Proposed outcome

An application's line may say `-` for its demo host: it isn't deployed on the demo host, and its registration there is refused, naming why. immo's line says `-`.

Success criterion: `registry.sh check` passes with immo's demo host `-`; a registration of such an application on the demo host is refused before anything changes.

## Affected users and systems

- Application (immo; any application not deployed on the demo host), Demo operator.
- `registry.txt`, `registry.sh`, `register-app.sh` (demo), `routes.sh`, README, `docs/migration.md`.

## Constraints

- 0004: the registry is checked by `up.sh` and `register-app.sh`; no two lines share a host name.
