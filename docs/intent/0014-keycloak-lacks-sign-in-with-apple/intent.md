# Intent: The shared Keycloak has no Sign in with Apple

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: change
- Source: conversation (immo's plan 0001, step 10, and spec 0001, PA-06, 2026-10-26)
- Spec needed: yes
- Status: proposed
- Opened: 2026-10-26
- Decided: —
- Supersedes: —

## Problem

immo (the immobilier.pf rewrite, about to register with the stack) lets its visitors sign in with an e-mail address, Google, Facebook or Apple, as the application it replaces does. Keycloak has no Apple identity provider of its own, and Apple departs from OpenID Connect: the token response is POSTed when scopes are requested, there is no userinfo endpoint, the name and the address come at the first authorization only, and the client secret is a JWT signed with a `.p8` key.

The stack's image installs no extension: `keycloak/Dockerfile` adds none, and its `/opt/keycloak/providers` holds only Keycloak's `README.md` (measured on `quay.io/keycloak/keycloak:26.7`, which is 26.7.5 on 2026-10-26). Keycloak's own social providers are eleven, none of them Apple's (BitBucket, Facebook, GitHub, GitLab, Google, LinkedIn, Microsoft, Openshift v4, PayPal, StackOverflow, Twitter: the list a throwaway 26.7.5 reports, the extension's `apple` aside). No application's realm can hold an `apple` identity provider, and immo's tests, which start a Keycloak of the stack's version with the same extensions, can't either. immo's plan 0001 keeps its step 10 waiting for this change.

## Proposed outcome

An application's realm on the shared Keycloak may hold an identity provider of type `apple`, in dev and on the demo host, created by its realm's import. The README says which extensions the image carries, at which version, and how that version follows Keycloak's.

Success criterion: the image built in dev (`up.sh`) and by the demo workflow lists `apple` among Keycloak's social providers, and a realm imported with an `apple` identity provider (disabled, without credentials) keeps it.

## Affected users and systems

- Application (immo first; any application whose users sign in with Apple), Developer, Demo operator, Demo visitor.
- Shared stack (`keycloak/Dockerfile`, the image `up.sh` builds), deployment workflow (`.github/workflows/deploy-demo.yml` builds and pushes the same image), README.
- New: a third party's code inside the Keycloak every application shares.

## Constraints

- High-risk under the project's risk rules: authentication. The extension runs inside the shared Keycloak, with access to every realm.
- It implements Keycloak's internal SPIs (Keycloak logs `KC-SERVICES0047 … is implementing the internal SPI social` for it): its version follows Keycloak's, and a Keycloak upgrade (0013 proposes 26.8.1) waits for a compatible release.
- The build stays reproducible: a pinned release, checked before Keycloak's build. The demo workflow tags the image by `keycloak/`'s tree, so changing the extension rebuilds the image and restarts Keycloak once, for every application, at the next `up.sh` in dev and the next deployment on the demo host.
- No Apple credentials in the stack nor in any realm export: an application types them in the console (immo's former `.p8` keys are compromised and are never reused).

## Open questions

- Which release, pinned and checked how? Research of 2026-10-26: `klausbetz/apple-identity-provider-keycloak` 1.17.0 (2026-01-15, the latest), built against Keycloak 26.5.0; its README's compatibility list gives `>= 1.17.0` for Keycloak `>= 26.5.0`. Its asset `apple-identity-provider-1.17.0.jar` (19,748 bytes) has the SHA-256 `4091dee2a1ec9e0771bef4bd46005197d86b0a2b1f25198c41738476b1d102bb`: GitHub's asset digest, a local computation and the release's own `.sha512` file agree. — the spec (tech lead)
- Does it work on the stack's Keycloak? Measured in throwaway containers (`start-dev`, file database), the JAR in `/opt/keycloak/providers` before `kc.sh build`: Keycloak 26.7.5, and 26.8.1 with 0013's features (`token-exchange-delegation,parameterized-scopes,cimd`), start, list `apple` among their social providers, and create and read back a disabled identity provider `apple` in a realm. A full sign-in needs an Apple developer account and a new key: not measured. — the spec; immo for the sign-in
- 0013 moves Keycloak to 26.8.1: which merges first, and does the second one check the extension again on its Keycloak? — tech lead
- Is a pinned, checked release enough for a third party's code in the shared Keycloak, or is each version's source read before it is pinned? Open on the project: #117, #120 and #122 (callback, token exchange); #115 ("Keycloak 26.5.2 - Unable to generate JWS") closed with no linked fix. — product owner, tech lead
- *Suggested solution* (immo's PA-06, decided there for immo): build arguments `APPLE_IDP_VERSION` and `APPLE_IDP_SHA256`; the release's JAR added to `/opt/keycloak/providers/` before `kc.sh build` with `ADD --chown=keycloak:root --chmod=644 --checksum=sha256:${APPLE_IDP_SHA256}` (measured with Docker 29.8.2 and buildx 0.35: the arguments expand, a wrong checksum fails the build with `digest mismatch` and tags nothing; it needs a BuildKit builder, which dev's compose build and the workflow's build-push-action both use; `ADD` alone leaves the file mode 600, Keycloak's container guide adds `--chmod=644`); the README lists the image's extensions and states "the extension's version follows Keycloak's". — the spec
