# Intent: The migration guide offers a GitLab CI job the demo host doesn't serve

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: change
- Source: conversation (the product owner's decision of 2026-10-28, after 0028's delivery)
- Spec needed: yes
- Status: specified
- Opened: 2026-10-28
- Decided: 2026-10-28
- Supersedes: —
- Mode: bootstrap

## Problem

The product owner decided on 2026-10-28 that the demo host deploys GitHub projects only; GitLab projects (immo) will be deployed on a Kubernetes cluster at Scaleway, by a pipeline still to define. Intent 0028 had just added to `docs/migration.md`, demo step 5, a paragraph "On another platform (GitLab, any CI that runs a shell)…", and mentions of GitLab's registry (`:163`): a GitLab project reading the guide is led to prepare a deployment onto the demo host that won't be offered, and the guide states a scope the stack no longer has.

## Proposed outcome

The guide and the README say which projects the demo host deploys (GitHub projects, through their workflow), and that a GitLab project isn't deployed by this stack, without describing its other target (the product owner, 2026-10-28: still to define); no step suggests deploying a GitLab project onto the demo host. What 0028 fixed for every project (ports, public images, the registry token on stdin) stays.

## Affected users and systems

- Personas: Application (a project migrating onto c4-infra); Demo operator
- Modules / systems: docs (`docs/migration.md`, `README.md`, `docs/demo-setup.md`)

## Constraints

- `tests/0002-workflow.sh` and `tests/0004-registry.sh` read the guide's GitHub example and its dev section: they keep passing.

## Open questions

- None (settled 2026-10-28: the docs say "not this stack", nothing of the other target).
