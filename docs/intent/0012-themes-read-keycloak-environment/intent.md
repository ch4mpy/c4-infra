# Intent: An application's Keycloak theme may read the shared Keycloak's environment

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: bug
- Source: conversation (security review of 0009, PRs #1 and #2, 2026-10-23: a pre-existing finding)
- Spec needed: yes
- Status: specified
- Opened: 2026-10-23
- Decided: 2026-10-23
- Supersedes: —

## Problem

Each application registers its Keycloak themes with the shared stack (`register-app.sh --themes`, `sudo c4-app register --themes` on the demo host), and they are copied as they are into the directory Keycloak reads. Nothing checks what a theme holds.

Keycloak's container environment holds the stack's secrets: the master realm's administrator password (`C4_MASTER_ADMIN_PASSWORD`, since 0009 the live, permanent one), the database's password, and Mailpit's SMTP password. The security review reports that Keycloak resolves `${env.NAME}` in a theme's `theme.properties`. If so, one property of one registered theme, rendered on a public login page, would show any visitor a secret that opens every application's realm. This could come from a careless or third-party theme as well as from a hostile one.

Observation: not reproduced in a throwaway Keycloak of the stack's image (26.7.4, 2026-10-23), with a login theme whose parent is `keycloak.v2` and `kcLoginClass=probe-${env.PROBE_SECRET}`. Neither the class nor the value showed on the login page. This doesn't settle it either way: the property may be unused by that template, or `${env.…}` may not be resolved there.

## Proposed outcome

No registered theme can bring a value of the shared Keycloak's environment into a page it renders, in dev and on the demo host. Success criterion: a theme that tries to (in `theme.properties`, a template, or a message bundle) is refused at registration, or the stack's secrets are out of its reach.

## Affected users and systems

- Application (its themes), Demo operator, Demo visitor.
- Registration (`register-app.sh`), demo stack (`demo/c4-app`), dev stack and demo stack (Keycloak's environment).

## Constraints

- High-risk under the project's risk rules: secrets, the isolation between applications.
- 0011's accepted risk covers paths that need a hostile file in an application's deployment, that is a leaked deployment key. This path differs on two counts: the leak is public, shown to any visitor, and it needs no hostile intent.
- The applications' themes keep working, `${…}` placeholders of their own included.

## Open questions

- Does Keycloak 26 resolve `${env.NAME}`, or system properties, in `theme.properties`, in templates, or in message bundles? — the spec, by measuring.
- Is this path inside 0011's accepted risk (it needs a file in an application's deployment), or out of it (a public leak, a third-party theme)? — product owner
- *Suggested solutions*: registration refuses themes that use `${env.`; the administrator's password is given to a one-shot import only and is gone from Keycloak's running environment. To be settled in the spec. — tech lead
