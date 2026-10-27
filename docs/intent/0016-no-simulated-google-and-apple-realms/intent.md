# Intent: The shared Keycloak offers no simulated Google or Apple provider to try a social login

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: change
- Source: conversation (2026-10-26; the spec of intent 0056 of the skills repository, `ch4mpy/claude`)
- Spec needed: yes
- Status: proposed
- Opened: 2026-10-26
- Decided: —
- Supersedes: —

## Problem

The applications on the stack let individuals sign in with Google or Apple (immo; any B2C project the skills generate). Neither can be tried on the stack:

- Keycloak, not the application, receives a provider's answer, at `https://host.docker.internal/auth/...` in dev. Google refuses a return address outside the public suffix list, so it can't serve the dev host; on the demo host each application needs its own Google Cloud project and OAuth client.
- Apple needs a third party's extension in the shared Keycloak (intent 0014), an Apple developer account and keys, and a public return address too.

So a Developer can't try a social login, nor how a Google or Apple account meets a local one, without real accounts and credentials, and not at all in dev.

## Proposed outcome

The stack provides two simulated providers, realms of the shared Keycloak named after Google and Apple, each with a login theme that recalls the original's, in dev and on the demo host. An application's realm declares them as OpenID Connect providers and its users sign in through them as they would through Google or Apple, with seeded accounts and no external service.

Success criterion: in dev and on the demo host, an application whose realm declares the simulated Google provider lets a seeded account sign in through it and come back logged in; likewise for Apple.

## Affected users and systems

- Developer, Application, Demo operator, Demo visitor.
- Shared stack (Keycloak, its realms and themes), registration (how an application gets what its realm needs from the simulated realms), README.

## Constraints

- High-risk under the project's risk rules: authentication, and the isolation between applications (several applications share the two realms).
- The themes recall the originals without their logos or brands presented as genuine, and say they are simulated providers: the demo host serves them publicly.
- No realm points to Google's or Apple's real services, and no credential of theirs is in the stack.
- Independent of intent 0014 (Apple's real provider, through an extension): either can be delivered first.

## Open questions

- Their names (`google`, `apple`, or a prefix the registry reserves for the stack), and whether the registry's checks reserve them. — Stage 2
- How an application gets its client in each simulated realm (a client per application created at registration, or one shared client), and its return address on each host. — Stage 2
- Which accounts are seeded, and whether an application may add its own. — Stage 2, then the PO
