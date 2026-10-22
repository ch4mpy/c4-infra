# Spec: Deploying to the demo host gives every application's workflow the whole host

- Intent: [0002](intent.md)
- Status: draft
- Version: 1
- Risk: high (rules: secrets, the isolation between applications, what a host exposes; tech lead's agreement required)
- Policies applied: none yet; standing constraints: README design, `docs/demo-setup.md`, `docs/migration.md`
- Approved: —

## Summary

Each application deploys to the demo host with its own account, which can act on its own compose project and registration only, through a fixed set of commands; the shared stack keeps its own account. Deployments pin their actions by commit and refuse to run without the host's known key.

## Requirements

- REQ-1 Each application's deployment credential gives access to one account on the host, its own, which can neither read nor change another application's files, containers, volumes or secrets, nor the shared stack's (PA-1 decided). (intent: proposed outcome)
- REQ-2 That account can do what a deployment needs and nothing else: copy its own deployment files, pull its images, start and stop its own compose project, and register itself (`register-app.sh --app <its name>`). (intent: proposed outcome)
- REQ-3 The shared stack's deployment keeps an account of its own, the only one that can change the shared services. (intent)
- REQ-4 Every action of the deployment workflows that receives a secret is pinned by commit, in c4-infra and in the deployment `docs/migration.md` describes for the applications. (intent: action pinned by tag)
- REQ-5 A deployment refuses to run when the host's key isn't pinned (`VPS_KNOWN_HOSTS`): no trust on first use. (intent: host key)
- REQ-6 `docs/demo-setup.md` and `docs/migration.md` describe how an application gets its account and key. (intent)

## Out of scope

- An orchestrator, several hosts, or per-application Docker daemons (PA-1 B).
- The applications' own workflows: each application's migration.

## Design

### Current behaviour

- `demo/vps-bootstrap.sh`: one `deploy` user, member of the `docker` group (root-equivalent), every workflow's key in its `authorized_keys`.
- `.github/workflows/deploy-demo.yml`: `webfactory/ssh-agent@v0.10.0` (a tag); without `VPS_KNOWN_HOSTS`, `ssh-keyscan` trusts whatever the host presents, with a warning.

### Behaviour per persona

- Demo operator: creates one account per application (a step of `vps-bootstrap.sh` or its successor), with that application's key.
- Application: deploys and registers itself only.

### API and contracts

- The host: one account per application, plus the shared stack's; the commands each may run (settled in the plan, PA-1).
- The workflows: `VPS_KNOWN_HOSTS` becomes required.

### User interface

None.

### Data

None.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| README design (applications' containers on the `c4-infra` network, unique names) | unchanged; the restriction is on who deploys (REQ-1, REQ-2) |
| No password on a command line (`CLAUDE.md`) | unchanged |

## Points of attention

### PA-1 How an application's account is confined

- Issue: anyone in the `docker` group is root; an application's deployment needs Docker for its own project only.
- Options: A one account per application without the `docker` group, allowed through `sudo` to run root-owned deployment commands for its own directory and name only / B rootless Docker, one daemon per application (but the shared `c4-infra` network can't span daemons) / C keep the shared `deploy` account, and only pin the actions and the host key (REQ-4, REQ-5)
- Recommendation: A: confines each application at a moderate cost, before the demo host exists; C is acceptable only if the demo's blast radius is (intent's question).
- Decides: PO (the blast radius), tech lead (the mechanism)
- Decision: to decide

## Acceptance criteria

- AC-1 Given Faito's deployment key, when it tries to read Hurura'a's `.env`, list or stop another application's containers, or run `docker` directly, then it is refused. (REQ-1)
- AC-2 Given Faito's deployment key, when its workflow deploys and registers Faito, then the deployment succeeds. (REQ-2)
- AC-3 Given an application's key, when it runs `register-app.sh --app hururaa`, then it is refused. (REQ-2)
- AC-4 Given a workflow without `VPS_KNOWN_HOSTS`, when it runs, then it fails before connecting. (REQ-5)
- AC-5 The workflows' actions that receive a secret are referenced by a 40-character commit SHA. (REQ-4)

## Intent questions

- Is the demo's blast radius acceptable as it is → PA-1.

## Change log

- v1 — 2026-10-21 — first version
