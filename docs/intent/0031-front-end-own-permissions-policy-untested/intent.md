# Intent: No test proves that a front end's own Permissions-Policy reaches the browser unchanged

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

0015's `headers=app` gives a front end its own Content-Security-Policy, `X-Frame-Options` and `Permissions-Policy`. `tests/0015-headers.sh`'s front end sends its own policy and `X-Frame-Options`, never its own `Permissions-Policy`: that one is proven only by its verifier's run by hand (0015's evidence). immo is about to rely on all three.

## Proposed outcome

A test proves that each of the three headers a front end sends on a `headers=app` route reaches the browser once, with its value, in dev and in the demo's configuration; a `ui` route with `headers=app` included.

## Affected users and systems

- Personas: Application (its front end's policy)
- Modules / systems: reverse proxy (`caddy/`, `routes.sh`), its tests

## Constraints

- 0015's behaviour doesn't change: a test only, unless it fails.

## Open questions

- None.
