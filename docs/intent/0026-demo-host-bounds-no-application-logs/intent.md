# Intent: The demo host doesn't bound the logs of an application's containers

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: change
- Source: conversation (the alignment analyses of Tickee and poc-immo-pf on c4-infra, 2026-10-28)
- Spec needed: yes
- Status: planned
- Opened: 2026-10-28
- Decided: 2026-10-28
- Supersedes: —
- Mode: bootstrap

## Problem

An application deployed with `sudo c4-app` can't set its containers' `logging:` (outside the allowlist of `demo/c4-app`), and Docker's default `json-file` driver keeps what a container writes on its standard output without limit: a talkative application, its database or its directory fill the demo host's disk, the shared stack's with it. c4-infra's own services rotate theirs (`compose.yml`, `default-logging`). The stack's Loki (`grafana-lgtm`) receives what an application exports in OTLP, but keeps it in its volume with no retention set, and doesn't replace what Docker writes.

## Proposed outcome

The logs of an application's containers on the demo host are bounded, whatever the application sets; what an application sends to the stack's Loki is kept for a bounded time.

## Affected users and systems

- Personas: Application (Tickee, immo); Demo operator
- Modules / systems: demo host (`demo/c4-app`, `demo/vps-bootstrap.sh`), observability (`grafana-lgtm`)

## Constraints

- 0002 and 0007 hold: no `docker` group for an application's account, nothing of another application's within its reach.

## Open questions

- The bound set by the host (the Docker daemon's log options, every container) or allowed per service (`logging` with a bounded driver) — the spec.
- Whether the applications' logs also go to Loki, through OTLP from each application or by the collector reading Docker's files (which would read every application's) — the spec, with Loki's retention.
