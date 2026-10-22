# Intent: Deploying to the demo host gives every application's workflow the whole host

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: change
- Source: conversation (security review of the shared stack, 2026-10-21)
- Spec needed: yes
- Status: specified
- Opened: 2026-10-21
- Decided: 2026-10-21
- Supersedes: —

## Problem

On the demo host, the shared stack and every application deploy as the same `deploy` user (`demo/vps-bootstrap.sh`), a member of the `docker` group, which amounts to root. Each application's GitHub workflow holds a key to it.

- A compromised workflow or repository of any one application (a leaked secret, a malicious dependency in its build) can read or change every other application's containers, databases and secrets, and the shared Keycloak with every realm.
- The deployment step uses `webfactory/ssh-agent` pinned by tag (`v0.10.0`), not by commit: whoever controls that tag receives the private key on the next run.
- When the `VPS_KNOWN_HOSTS` secret isn't set, the workflow trusts whatever host key the VPS presents (a warning is printed), so a redirected connection would receive every secret of the deployment.

The applications' deployments follow the same pattern (`docs/migration.md`), so the blast radius grows with each migrated application.

## Proposed outcome

A compromised application's deployment can affect that application only, and a deployment never sends secrets to a host whose identity isn't established. Success criterion: with one application's deployment key, another application's containers and the shared Keycloak's data can't be read or changed; a deployment without a pinned host key refuses to run.

## Affected users and systems

- Demo operator; Application (every application deploying to the demo host); Demo visitor (their data in every application).
- Demo stack (`demo/`), deployment workflow, `docs/migration.md` (what applications do).

## Constraints

- The demo is sized for a single small VPS: no orchestrator.
- Registration (`register-app.sh`) needs to reach the shared Keycloak, RabbitMQ and reverse proxy.

## Open questions

- Is the demo's blast radius acceptable as it is, given what the demo holds (dev-like data, public demo users)? — PO.
