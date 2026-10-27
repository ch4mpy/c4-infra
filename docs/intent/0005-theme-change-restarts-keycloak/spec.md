# Spec: A theme change restarts the Keycloak every application uses

- Intent: [0005](intent.md)
- Status: approved
- Version: 1
- Risk: standard (no risk rule applies: authentication itself doesn't change, only how themes are loaded)
- Policies applied: none yet; standing constraints: README design
- Approved: 2026-10-21, Jérôme Wacongne (PO)

## Summary

In dev, Keycloak doesn't cache themes, and a registration installs a new or changed theme without restarting it: re-running the registration, then reloading the login page, shows the change (PA-01). On the demo host, caching stays on and only a changed theme restarts Keycloak, as today.

## Requirements

- **RQ-01:** In dev, Keycloak caches neither themes nor templates, and its static resources aren't cached by browsers. (intent: proposed outcome)
- **RQ-02:** In dev, `register-app.sh` installs a new or changed theme without restarting Keycloak. (intent: success criterion)
- **RQ-03:** A developer iterating on a theme re-runs the registration (`deploy-dev.sh`, or `register-app.sh --themes`), then reloads the login page to see the change (PA-01 decided). (intent: success criterion, narrowed)
- **RQ-04:** On the demo host, theme caching stays on, and Keycloak is restarted only when a theme a registration installs differs from the installed one — today's behaviour, kept. (intent: constraint, "as little as possible")
- **RQ-05:** Dev and the demo host are told apart by the setting of the stack's `.env` that names its environment (`dev` or `demo`, 0003 RQ-07), never by the proxy in use, which becomes Caddy in both (0003 PA-01); whichever of the two specs is delivered first introduces it. (intent: constraint, production-like caching stays on the demo host; 0003)

## Out of scope

- Keycloak reading an application's theme directory live (PA-01 B).
- Zero-downtime theme updates on the demo host (one Keycloak node).

## Design

### Current behaviour

`register-app.sh`: when a theme differs from the installed copy, it is copied into `keycloak/themes/` and Keycloak is restarted ("Restarting Keycloak to load the themes"), in dev as on the demo host; an unchanged theme restarts nothing. The only difference `register-app.sh` sees between the two is `PROXY` (`nginx` in dev, `caddy` written by `deploy-demo.yml`).

### Behaviour per persona

- Developer: theme changes show on reload after a registration; other applications' sessions are untouched.
- Demo visitor: unchanged, a short Keycloak restart when a deployment changes a theme.

### API and contracts

- Dev Keycloak's options for theme caching (the exact option names of the Keycloak version in use, settled in the plan), in the dev part of the compose files (0003 PA-02).

### User interface

None.

### Data

None.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| README design (one Keycloak for every application) | RQ-02: no restart in dev |

## Points of attention

### PA-01: What a developer does to see a theme change (decided)

- Issue: the intent's criterion is "edit and reload"; Keycloak reading each application's theme directory live needs one mount per application in a shared stack.
- Options: A re-run the registration, then reload (no cache, no restart) / B edit and reload, Keycloak reading the application's directory live
- Recommendation: A: one command more, no change to the shared stack's mounts; the intent's criterion is narrowed on purpose.
- Decides: PO
- Decision: A, re-run the registration then reload (PO, 2026-10-21)

## Acceptance criteria

- **AC-01:** Given a theme registered in dev, when one of its templates is edited and the registration re-run, then the login page shows the change on reload, and Keycloak's container wasn't restarted (same start time). (RQ-01, RQ-02, RQ-03)
- **AC-02:** Given another application logged in, when the theme changes in dev, then its session stays valid. (RQ-02)
- **AC-03:** Non-regression on the demo host: when a deployment installs an unchanged theme, Keycloak isn't restarted; when it installs a changed one, it is, once. (RQ-04)
- **AC-04:** Given the stack's environment set to `dev` with Caddy as its proxy, when a changed theme is registered, then Keycloak isn't restarted; set to `demo`, it is. (RQ-05)

## Intent questions

- None.

## Change log

- v1 — 2026-10-21 — first version
- v1 — 2026-10-21 — draft: coherence review (the intent's criterion narrowed by a decision, demo behaviour stated as kept, dev/demo setting shared with 0003), PA-01 decided
- v1 — 2026-10-21 — draft: second coherence review (the environment named in `.env` rather than told by the proxy, criterion AC-04)
- v1 — 2026-10-21 — approved by the PO: every point of attention decided
