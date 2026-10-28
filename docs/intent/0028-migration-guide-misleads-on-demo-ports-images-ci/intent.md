# Intent: The migration guide misleads a project on its demo ports, the images it may run and its CI's platform

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: change
- Source: conversation (the alignment analyses of Tickee and poc-immo-pf on c4-infra, 2026-10-28)
- Spec needed: no
- Status: delivered (2026-10-28)
- Opened: 2026-10-28
- Decided: 2026-10-28
- Supersedes: —
- Mode: bootstrap

## Problem

`docs/migration.md` and the README tell a project moving onto c4-infra less, or otherwise, than c4-infra does:

- its first step moves the project's dev ports into its block (`p080`, `p180`…), but never says that its `demo` profile keeps `7080`, `8080`…: the demo host's Caddy reaches `<app>.gateway:7080`, `<app>.frontend:80` (Tickee's analysis);
- "Every service runs an `image:` the project's CI built and pushed to a registry" (0011): only `build:` is refused; a public image (`postgres`, `openldap`) is pulled as any other;
- its workflow example is GitHub's only (Actions, GHCR); `sudo c4-app pull --registry <host> --registry-user <user>` works with any registry (immo is on GitLab);
- `README.md:554` says the demo host is "Not set up yet (postponed on 2026-10-21)": it has been deployed since 2026-10-23.

## Proposed outcome

The guide and the README say what a project needs to do, as c4-infra behaves: its demo ports, the images it may run, its registry and CI whatever their platform; no stale status.

## Affected users and systems

- Personas: Application (its developers migrating it); Demo operator
- Modules / systems: `docs/migration.md`, `README.md`

## Constraints

- What c4-infra does doesn't change: documentation only.

## Open questions

- None.
