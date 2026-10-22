# Spec: A theme change restarts the Keycloak every application uses

- Intent: [0005](intent.md)
- Status: draft
- Version: 1
- Risk: standard (no risk rule applies: authentication itself doesn't change, only how themes are loaded)
- Policies applied: none yet; standing constraints: README design
- Approved: —

## Summary

In dev, Keycloak doesn't cache themes: a theme installed or changed by a registration shows on the next page load, without a restart. On the demo host, caching stays on and a changed theme still restarts Keycloak, once per deployment that changes it.

## Requirements

- REQ-1 In dev, Keycloak caches neither themes nor templates, and its static resources aren't cached by browsers. (intent: proposed outcome)
- REQ-2 In dev, `register-app.sh` installs a new or changed theme without restarting Keycloak. (intent: success criterion)
- REQ-3 On the demo host, theme caching stays on (intent: constraint), and `register-app.sh` restarts Keycloak only when a theme it installs differs from the installed one. (intent: "as little as possible")
- REQ-4 A developer iterating on a theme re-runs the registration (or copies the files) and reloads the login page to see the change. (intent: success criterion)

## Out of scope

- Live-mounting an application's theme directory into the shared Keycloak (themes stay copied by the registration).
- Zero-downtime theme updates on the demo host (one Keycloak node).

## Design

### Current behaviour

`register-app.sh`: when a theme differs from the installed copy, it is copied into `keycloak/themes/` and Keycloak is restarted ("Restarting Keycloak to load the themes"), in dev as on the demo host.

### Behaviour per persona

- Developer: theme changes show on reload; other applications' sessions are untouched.
- Demo visitor: unchanged, except a short Keycloak restart when a deployment changes a theme.

### API and contracts

- Dev Keycloak's options for theme caching (the exact option names of the Keycloak version in use, settled in the plan).

### User interface

None.

### Data

None.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| README design (one Keycloak for every application) | REQ-2: no restart in dev |

## Points of attention

None.

## Acceptance criteria

- AC-1 Given a theme registered in dev, when one of its templates is edited and the registration re-run, then the login page shows the change on reload, and Keycloak's container wasn't restarted (same start time). (REQ-1, REQ-2, REQ-4)
- AC-2 Given another application logged in, when the theme changes in dev, then its session stays valid. (REQ-2)
- AC-3 Given the demo host, when a deployment installs an unchanged theme, then Keycloak isn't restarted; when it installs a changed one, it is, once. (REQ-3)

## Intent questions

- None.

## Change log

- v1 — 2026-10-21 — first version
