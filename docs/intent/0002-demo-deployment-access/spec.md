# Spec: Deploying to the demo host gives every application's workflow the whole host

- Intent: [0002](intent.md)
- Status: draft
- Version: 1
- Risk: high (rules: secrets, the isolation between applications, what a host exposes; tech lead's agreement required)
- Policies applied: none yet; standing constraints: README design, `docs/demo-setup.md`, `docs/migration.md`
- Approved: —

## Summary

Each application deploys to the demo host with its own account, outside the `docker` group. It registers itself through one root-owned command, which acts only on what the registry (0004) assigns to that application — its realms, its RabbitMQ user, its themes, its host names — with the shared stack's registration credential (0006), which no application's account can read. Deployments pin their actions by commit and refuse to run without the host's known key.

## Requirements

- REQ-1 Each application's deployment credential opens one account on the host, its own, which can neither read nor change another application's files, containers, volumes or secrets, nor the shared stack's, `.env` and registration credential included (PA-1 decided). (intent: proposed outcome)
- REQ-2 That account can copy its own deployment files, pull its images, start and stop its own compose project, and register itself — and nothing else. (intent: proposed outcome)
- REQ-3 Registering as an application acts only on what the registry assigns to it (0004): its realms (the realms named in its entry; importing, resetting or deleting another realm is refused), its RabbitMQ user and virtual host, its themes (the theme names in its entry; installing or replacing another one is refused), and a server block that serves its host names only and routes only to its own containers. (intent: proposed outcome)
- REQ-4 The registration credential (0006) is held by the shared stack only; registrations run as root-owned commands that use it on the application's behalf. (intent; 0006)
- REQ-5 The shared stack's deployment keeps an account of its own, the only one that can change the shared services. (intent)
- REQ-6 Every action of the deployment workflows that receives a secret is pinned by commit, in c4-infra and in the deployment `docs/migration.md` describes for the applications. (intent: action pinned by tag)
- REQ-7 A deployment refuses to run when the host's key isn't pinned (`VPS_KNOWN_HOSTS`): no trust on first use. (intent: host key)
- REQ-8 `docs/demo-setup.md` and `docs/migration.md` describe how an application gets its account and key. (intent)

## Out of scope

- What a compromised application's containers can reach at runtime on the shared `c4-infra` network (Mailpit without authentication inside the network, Keycloak's plain HTTP port, the other applications' containers and actuators): a need of its own, to be opened as an intent.
- An orchestrator, several hosts, or per-application Docker daemons.
- The applications' own workflows: each application's migration.

## Design

### Current behaviour

- `demo/vps-bootstrap.sh`: one `deploy` user, member of the `docker` group (root-equivalent), every workflow's key in its `authorized_keys`.
- `register-app.sh` ties only the RabbitMQ virtual host to `--app`: the realm comes from the file's name (and `--reset-realms` deletes it), `--rabbitmq-user` can name any user, `--themes` replaces any theme name, `--proxy` installs any block; it runs `docker exec` into the shared containers with the bootstrap administrator's password from `~/c4-infra/.env`.
- `.github/workflows/deploy-demo.yml`: `webfactory/ssh-agent@v0.10.0` (a tag); without `VPS_KNOWN_HOSTS`, `ssh-keyscan` trusts whatever the host presents, with a warning.

### Behaviour per persona

- Demo operator: creates one account per application, with that application's key, and its registry entry (0004).
- Application: deploys and registers itself only.

### API and contracts

- The host: one account per application, plus the shared stack's; the root-owned registration command each application's account may run, for its own name only.
- The registry entry (0004) is what a registration may touch.
- The workflows: `VPS_KNOWN_HOSTS` becomes required.

### User interface

None.

### Data

None beyond the registry (0004).

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| README design (applications' containers on the `c4-infra` network, unique names) | unchanged; the restriction is on who deploys and registers (REQ-1 to REQ-4) |
| No password on a command line (`CLAUDE.md`) | unchanged |

## Points of attention

### PA-1 How an application's account is confined (decided)

- Issue: anyone in the `docker` group is root; an application's deployment needs Docker for its own project only, and registration needs the shared services.
- Options: A one account per application without the `docker` group, allowed through `sudo` to run root-owned deployment and registration commands for its own directory and registry entry only / B rootless Docker, one daemon per application (but the shared `c4-infra` network can't span daemons) / C keep the shared `deploy` account, and only pin the actions and the host key (REQ-6, REQ-7)
- Recommendation: A: confines each application at a moderate cost, before the demo host exists.
- Decides: PO (the blast radius), tech lead (the mechanism)
- Decision: A, one account per application (PO and tech lead, 2026-10-21)

## Acceptance criteria

- AC-1 Given Faito's deployment key, when it tries to read Hurura'a's `.env` or `~/c4-infra/.env`, list or stop another application's containers, or run `docker` directly, then it is refused. (REQ-1)
- AC-2 Given Faito's deployment key, when its workflow deploys and registers Faito, then the deployment succeeds. (REQ-2)
- AC-3 Given Faito's deployment key, when it registers with Hurura'a's realm file (`public-facing`), `--reset-realms`, Hurura'a's RabbitMQ user, Tickee's theme (`--themes` holding `tickee`), or a server block for `hururaa.c4-soft.com` or routing to `keycloak:8080`, then each is refused, and Tickee's theme is left as it was. (REQ-3)
- AC-4 Given an application's account, then it can't read the registration credential. (REQ-4)
- AC-5 Given a workflow without `VPS_KNOWN_HOSTS`, when it runs, then it fails before connecting. (REQ-7)
- AC-6 The workflows' actions that receive a secret are referenced by a 40-character commit SHA. (REQ-6)
- AC-7 Given every application's account outside the `docker` group, when c4-infra's own workflow deploys, then it updates and restarts the shared stack with the shared stack's account; with an application's key, the same commands are refused. (REQ-5)
- AC-8 Given a host prepared by `docs/demo-setup.md`, when the demo operator follows it and `docs/migration.md` to add Faito (its account, its key, its registry entry), then AC-2's deployment succeeds without any other step. (REQ-8)

## Intent questions

- Is the demo's blast radius acceptable as it is → PA-1: no.

## Change log

- v1 — 2026-10-21 — first version
- v1 — 2026-10-21 — draft: coherence review (registration scoped by the registry, credential held by the shared stack, runtime lateral movement out of scope), PA-1 decided
- v1 — 2026-10-21 — draft: second coherence review (themes scoped by the registry entry, criteria for REQ-5 and REQ-8)
