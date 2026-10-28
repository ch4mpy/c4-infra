# Intent: An application can't tell which Keycloak its tests should run

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: change
- Source: conversation (the alignment analyses of Tickee and poc-immo-pf on c4-infra, 2026-10-28)
- Spec needed: yes
- Status: accepted
- Opened: 2026-10-28
- Decided: 2026-10-28
- Supersedes: —
- Mode: bootstrap

## Problem

An application tests against a Keycloak of its own (Testcontainers). immo runs `quay.io/keycloak/keycloak:26.7`, a floating tag, while the shared stack runs 26.8.1, pinned, with `token-exchange-delegation`, `parameterized-scopes` and `cimd`, its own login themes and simulated realms (0013, 0016). Nothing in c4-infra says which image, version or features an application should test with, nor tells it when they change: immo drifted without anyone seeing it (poc-immo-pf's analysis, 2026-10-28), and its tests prove less than they seem.

## Proposed outcome

An application's tests can run the same Keycloak as the shared stack (version, features, and what the stack adds to it), and learn when it changes.

## Affected users and systems

- Personas: Application (its developers, its CI)
- Modules / systems: `keycloak/` (the image), the deployment workflow (`.github/workflows/deploy-demo.yml`, which pushes it to GHCR), `README.md`

## Constraints

- An application's CI may run on another platform than c4-infra's (immo: GitLab).

## Open questions

- Publish the image the workflow pushes (its tag is its directory's content), a readable version and feature list, or both — the spec.
