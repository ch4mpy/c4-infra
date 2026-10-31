# Spec: The registry demands a demo host of an application the demo host never deploys

- Intent: [0045](intent.md)
- Status: approved
- Version: 1
- Risk: standard (no risk rule applies: the registry's format and a refusal; no authentication, secret, isolation between applications, network exposure or personal data changes)
- Policies applied: none yet; standing constraints: 0004 (the registry checked by `up.sh` and `register-app.sh`, no host name shared), 0032 (the demo host deploys GitHub projects only)
- Approved: 2026-10-30, Jérôme Wacongne (PO, also tech lead; in the session)

## Summary

`registry.txt` accepts `-` as an application's demo host: the application isn't deployed on the demo host. `registry.sh` reads it as no demo host, and `register-app.sh` refuses such an application on the demo host before anything changes. immo's line says `-`.

## Requirements

- **RQ-01:** `registry.sh check` accepts `-` in the demo-host column, claims no host name for it, and still requires a dev host. (intent: proposed outcome)
- **RQ-02:** `registry_entry` gives an empty `REG_DEMO_HOST` for `-`, and `registry.sh entry` prints `demo_host=`. (intent: proposed outcome)
- **RQ-03:** On the demo host (`INFRA_ENV=demo`), `register-app.sh` refuses an application whose demo host is `-`, naming it and why, before any change. In dev, nothing changes. (intent: success criterion)
- **RQ-04:** immo's line of `registry.txt` says `-` as its demo host. (intent: success criterion)
- **RQ-05:** `registry.txt`'s header and `docs/migration.md` say what `-` means there. (intent: proposed outcome)

## Out of scope

- immo's deployment on Kubernetes (its own pipeline).
- The other applications' lines.

## Design

### Current behaviour

`registry.sh:205-207` checks both hosts against a host-name pattern, so `-` is refused; `:244-247` claims each host and its MCP origin. `registry_entry` (`:253-270`) turns `-` into an empty value for the realms, the RabbitMQ user and the themes only. `routes.sh:94` takes `REG_DEMO_HOST` as the site's host on the demo host. `register-app.sh:146` reads the entry, after `INFRA_ENV` is checked (`:103`).

### Target behaviour

- `registry.sh check`: the demo host is `-` or a host name; for `-`, no claim of it nor of its MCP origin.
- `registry_entry`: `-` as the demo host gives `REG_DEMO_HOST=`.
- `register-app.sh`, right after the entry is read, on the demo host: `<app> has no demo host in the registry (its line says "-"): it isn't deployed on the demo host; nothing was registered.`, exit 1.
- `registry.txt`: `5 immo immo - immo immo.dev.localhost -`.

## Acceptance criteria

- **AC-01:** Given a registry whose two lines say `-` as their demo host, when `registry.sh check` runs, then it passes; `registry.sh entry` of one prints `demo_host=`. (RQ-01, RQ-02)
- **AC-02:** Given such an application and `INFRA_ENV=demo`, when `register-app.sh` registers it, then it is refused, naming the application and the `-`, before any docker call. (RQ-03)
- **AC-03:** The repository's `registry.txt` passes `registry.sh check` with immo's demo host `-`. (RQ-04)
- **AC-04:** `registry.txt`'s header and `docs/migration.md` say that `-` as the demo host means "not deployed on the demo host". (RQ-05)

## Intent questions

None open.

## Change log

- v1, 2026-10-30: drafted and approved in the session.
