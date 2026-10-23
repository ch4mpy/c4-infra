# Intent: A theme change restarts the Keycloak every application uses

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: change
- Source: conversation (quality review of the shared stack, 2026-10-21)
- Spec needed: yes
- Status: delivered
- Opened: 2026-10-21
- Decided: 2026-10-21
- Delivered: 2026-10-23 (deployed with 0697208; PR #6)
- Supersedes: —

## Problem

Keycloak caches its themes. When an application's registration installs a changed theme, `register-app.sh` restarts the shared Keycloak so that it loads it: for about a minute, logins, token refreshes and the admin API fail for every application of the machine (in dev) or of the demo host. A developer iterating on a login theme (Tickee has one) takes the other applications down at each try, and only sees the change after a new registration.

## Proposed outcome

In dev, a theme change shows on the next page load, without restarting Keycloak; on the demo host, a theme update disturbs the other applications as little as possible. Success criterion: in dev, editing an application's theme and reloading its login page shows the change, while another application's session stays valid.

## Affected users and systems

- Developer, Application, Demo visitor.
- Dev stack and demo stack (Keycloak), registration.

## Constraints

- Production-like caching stays on the demo host.

## Open questions

- None.
