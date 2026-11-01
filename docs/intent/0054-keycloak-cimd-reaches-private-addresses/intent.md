# Intent: Keycloak fetches a client's metadata document from a private address when a trusted domain resolves to one

- Author: Jérôme Wacongne (product owner), from poc-immo-pf's intent 0021
- Kind: bug
- Source: conversation (poc-immo-pf 0021, `CimdIT`)
- Spec needed: yes
- Status: specified
- Opened: 2026-10-31
- Decided: 2026-10-31
- Supersedes: —
- Mode: bootstrap

## Problem

When an MCP client presents a client ID metadata document (CIMD) URL, the shared Keycloak (26.8.1, `cimd` enabled by 0013) fetches that document itself. A realm's `client-id-metadata-document` executor restricts the URL to trusted domains, and 0013's RQ-17 refuses at registration any trusted domain that names no public host. Nothing, however, checks where a trusted public domain resolves when Keycloak fetches the document. If a domain resolves to a private address, through a misconfigured or compromised DNS record or DNS rebinding, Keycloak sends an HTTP request to that address, inside the stack's networks or the host's. The executor's "private addresses refused" setting does not prevent it. Keycloak can therefore be made to call internal services (an application's database or REST API, RabbitMQ, the Grafana stack, the demo host's metadata endpoints), a server-side request forgery.

Steps to reproduce, from poc-immo-pf 0021's `CimdIT.givenTrustedDomainResolvingToPrivateAddress_whenAuthorize_thenDocumentRead_privateAddressNotRefused`:
1. Start Keycloak from c4-infra's published image, with a realm whose CIMD policy trusts a domain.
2. Make that domain resolve to a private address (a container alias) that serves a metadata document over `https`.
3. Start an authorization with that URL as `client_id`.

- Expected: the document is not fetched and the authorization is refused.
- Observed: Keycloak fetches the document and shows the consent screen.

Environment: c4-infra's Keycloak image (26.8.1), Testcontainers, 2026-10-31. Every realm whose policy opts into CIMD is exposed, in dev and on the demo host.

## Proposed outcome

On the shared stack, in dev and on the demo host, Keycloak cannot reach a private, loopback or link-local address when it fetches a CIMD document, whatever the trusted domain resolves to. The authorization fails and no request reaches the internal address. Fetching a document from a public address keeps working.

Success criterion: a test of c4-infra makes a trusted domain resolve to a private address serving a valid document, and shows that Keycloak neither fetches it nor shows the consent screen. The same test shows that a document on an allowed address is still read.

## Affected users and systems

- Application: realms that opt into CIMD, poc-immo-pf first.
- Demo visitor: an agent connected to an application.
- Modules: shared stack (`compose.yml`, `compose.dev.yml` or `compose.demo.yml`, Keycloak's network access) and demo host.

## Constraints

- High risk under the project's rules: authentication, and what a host exposes to the network.
- Keycloak still has to reach what it legitimately calls: its database, the applications' realms' identity providers (the Google simulator in dev, the real providers on the demo host), mail, and public CIMD hosts.
- 0013's RQ-17 stays in force.
- c4-infra forbids `--features` in an application's container (it would replace the image's).

## Open questions

- Is a fix in Keycloak itself (upstream issue, or a version that honours the setting at fetch time) enough, or does the stack filter Keycloak's outgoing traffic either way? Answered by: tech lead.
- Suggested solution (the requester's; the spec decides): an outgoing proxy or a network rule for Keycloak's HTTP client that denies private ranges. Answered by: tech lead.
- Are other Keycloak features that fetch URLs (identity providers' discovery, `jwks_uri` of clients, request objects) open to the same issue, and are they in this intent's scope? Answered by: tech lead.
