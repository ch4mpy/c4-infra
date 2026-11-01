# Spec: Keycloak fetches a client's metadata document from a private address when a trusted domain resolves to one

- Intent: [0054](intent.md)
- Status: draft
- Version: 1
- Risk: high (two risk rules apply: it touches authentication, an MCP client's registration by its metadata document, and what a host exposes to the network, the internal addresses Keycloak can be made to call)
- Policies applied: none (the project has no policy yet); standing constraints: README's design, 0007 (an application reaches none of the others), 0013's RQ-17, no `--features` in an application's container
- Approved: —

## Summary

The shared Keycloak (26.8.1, `cimd`) fetches an MCP client's metadata document from whatever address a trusted domain resolves to, private ones included: 26.8.1's `client-id-metadata-document` executor checks the URL's host name against the trusted domains, never the address it resolves to. On the shared stack, in dev and on the demo host, Keycloak's fetch of such a document is refused when the address is loopback, private, link-local or otherwise not public, no request reaches it, and the authorization fails; a document on a public address is still read. Where the refusal happens is PA-01.

## Requirements

- **RQ-01:** When Keycloak would fetch a client ID metadata document whose host resolves to a loopback, private, link-local, unique local, carrier-grade NAT, unspecified or multicast address, IPv4 or IPv6 (IPv4-mapped IPv6 included), the fetch is refused and no TCP connection reaches that address, in dev and on the demo host. (intent: proposed outcome)
- **RQ-02:** The authorization of such a client then fails: no consent screen, no login form, and no client is created in the realm. (intent: expected)
- **RQ-03:** The refusal holds against the address used for the connection itself, not against an earlier resolution: a name that resolves to a public address at a check and to a private one at the fetch (DNS rebinding) is refused, and so is a redirect to a private address. (intent: "whatever the trusted domain resolves to", DNS rebinding)
- **RQ-04:** A metadata document on a public address of a trusted domain is still read, and the authorization proceeds to the login and consent screens as today. (intent: proposed outcome, success criterion)
- **RQ-05:** Keycloak still reaches what it legitimately calls: its database, mail, the applications' gateways (back-channel logout), the simulated providers through the shared host, the real identity providers on the demo host, and public CIMD hosts. (intent: constraints)
- **RQ-06:** The refusal covers the other URLs that Keycloak fetches over HTTP from what an unauthenticated client presents (the `jwks_uri`, `sector_identifier_uri` and `request_uris` of a metadata document, a `request_uri` parameter), per PA-03. (intent: open question 3)
- **RQ-07:** 0013's RQ-17 stays in force, unchanged; the image still enables exactly `token-exchange-delegation`, `parameterized-scopes` and `cimd`. (intent: constraints)
- **RQ-08:** README says where the refusal lives, what Keycloak may still reach, and what an application's tests of the published image do (or don't) inherit (PA-04). (intent: affected users)

## Out of scope

- URLs a realm's author writes in the export (an identity provider's endpoints, a client's back-channel logout or `jwksUrl`): the realm's author is trusted as by 0013, and some of them name internal hosts on purpose (`host.docker.internal`, `<app>.gateway`).
- A Keycloak upgrade to 27.x: its own intent, when it ships (PA-02).
- The applications' own tests: poc-immo-pf's `CimdIT` private-address case is reviewed by poc-immo-pf with this intent's delivery.

## Design

### Current behaviour

- Reproduced by poc-immo-pf 0021's `CimdIT.givenTrustedDomainResolvingToPrivateAddress_whenAuthorize_thenDocumentRead_privateAddressNotRefused` (poc-immo-pf `backend/immo-api/src/test/java/pf/immobilier/it/CimdIT.java`, commit `018886f`): Keycloak from c4-infra's published image, the realm trusting `agent.cimd-test.example`, a Caddy container under that alias at a site-local address (the test asserts `isSiteLocalAddress()`); Keycloak reads the document and shows the consent screen.
- Keycloak 26.8.1's executor has no address check, and no setting for one. Its settings are `cimd-allow-http-scheme`, `cimd-allow-permitted-domains`, `cimd-required-properties`, `cimd-restrict-same-domain`, `cimd-resource-indicator-allow-list` and the provider's cache and size options (`AbstractClientIdMetadataDocumentExecutorFactory.java:43-59` at tag `26.8.1`). `verifyClientId` carries the comment "It checks if an address resolved … is loopback … is private address" (`AbstractClientIdMetadataDocumentExecutor.java:544-547`), but the `verifyUri` it calls checks the host against the trusted domains only. The intent's "private addresses refused" setting doesn't exist in 26.8.1: the comment, and poc-immo-pf 0021's PA-01 reading of it, are the source of that belief.
- The fetch goes through `SimpleHttp.create(session)` (`AbstractClientIdMetadataDocumentExecutor.java:592`), Keycloak's outgoing HTTP client, the one its "Configuring outgoing HTTP requests" guide configures (proxy mappings by host-name regex, `NO_PROXY`, `HTTPS_PROXY`; `allow-redirects` false by default, "to avoid redirects that could lead for example to server-side request forgery").
- Upstream: commit `f505504307` ("ssfr check for cimd", 2026-10-13, closes keycloak/keycloak#53812, labelled `release/27.0.0`) adds `cimd-allow-private-use-addresses` (default off): it resolves the host of the Client ID URL, `jwks_uri`, `sector_identifier_uri` and `request_uris` with `InetAddress.getAllByName` and rejects loopback, any-local, link-local, site-local, multicast, `fc00::/7`, `0.0.0.0/8` and `100.64.0.0/10`, even within the trusted domains. It is on `main` only: not in 26.8.1 (the latest release), not on `release/26.8`. It checks before the fetch, which resolves again: a rebinding between the two passes.
- Keycloak's legitimate private destinations (RQ-05): in dev, `host.docker.internal` (the host gateway: the gateways' back-channel logout, the simulated providers at `https://host.docker.internal/auth/realms/simulated-*`, SMTP on 1025; `compose.dev.yml:44-45`, README "Design"); on the demo host, every application's network (`networks.sh`), `<app>.gateway`, `mailpit`, and `INFRA_HOST`, which resolves to Caddy on those networks (`compose.demo.yml`, header); its database on `c4-infra.keycloak-db` (JDBC, not HTTP). A blanket refusal of private addresses at the network level would cut all of them.
- Docs consulted: Context7 was unavailable in this session (its MCP server isn't configured here); keycloak.org's release notes (CIMD experimental since 26.6.0; 26.8.0's Vert.x client keeps the outgoing-HTTP options) and "Configuring outgoing HTTP requests", and Keycloak's source at tag `26.8.1` and `main` instead. No keycloak.org page of 26.8 documents an address check for CIMD.

### Behaviour per persona

- Demo visitor (through an MCP client): a client whose document is on a public host of a trusted domain registers and is asked for consent as today; one whose domain resolves to an internal address gets Keycloak's error page, no consent screen.
- Application: nothing to change in its realm; a realm still trusts public domains only (RQ-17). Its tests of the published image get what PA-04 decides.
- Developer and demo operator: per PA-01, possibly one more service of the stack, started by `up.sh` and the deployment like the others; a refused fetch is visible in its log.

### API and contracts

- The refusal is Keycloak's existing failure of a metadata fetch: the authorization request ends on an error, never on the login or consent page, and no client is stored.
- Under PA-01 A: Keycloak's outgoing HTTP goes through a forward proxy of the stack (Keycloak's proxy-mapping options, runtime options, not features), except the internal names of PA-05; the proxy resolves each destination once, refuses the classes of RQ-01, connects to the address it checked, and logs each refusal with the host and the address.

### Data

None.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| README design: one image, its features only | RQ-07: no feature added; PA-01 A uses runtime options |
| 0007: an application reaches none of the others | RQ-01, RQ-06: an unauthenticated client can't make Keycloak call another application's container |
| 0013 RQ-17 | RQ-07: kept; PA-05 relies on it (a trusted domain never has an internal name's shape) |
| No `--features` in an application's container | RQ-07; PA-04 |

## Points of attention

### PA-01: Where the refusal happens

- Issue: 26.8.1 has no address check (Current behaviour); the stack must refuse on its own, now, or wait.
- Options:
  - A: an egress forward proxy for Keycloak's outgoing HTTP, on both environments: Keycloak's proxy mappings send every host but the internal names of PA-05 to it; it refuses the RQ-01 classes after resolving and connects to the address it checked. Covers CIMD and every other client-presented URL (RQ-06), closes rebinding and redirects (RQ-03), IPv6 by its rules. Costs: one more pinned image and service in both compose files (memory on the demo host, a pull per deployment), its rule set to maintain, fail-closed (proxy down: no CIMD, no real identity provider on the demo host until it is back). Leaves open: the internal names of PA-05, reached directly by design.
  - B: wait for Keycloak 27.0.0 and set `cimd-allow-private-use-addresses` off (PA-02). Costs: no fix until a release with no date, a major upgrade. Leaves open: rebinding between check and fetch, URLs outside the executor's list, any other fetch.
  - C: a network rule (iptables on the demo host, a Keycloak-only network): Keycloak must reach internal addresses on every application's network, so the rule is an allow-list of subnets that move at each registration, cannot tell a hostile name from `<app>.gateway` on the same subnet, and has no equivalent under Docker Desktop on Windows.
  - D: disable `cimd` until upstream ships the check: complete and cheap, but poc-immo-pf 0021's EX-12 falls back to anonymous DCR (0013's PA-05 reverted).
  - E: a provider JAR backporting upstream's check into the image: experimental internals overridden, to redo at each upgrade, rebinding still open.
- Recommendation: A, the only option that refuses at the connection itself and covers every client-presented fetch; B joins it as defence in depth once released (PA-02).
- Decides: tech lead
- Decision: to decide

### PA-02: The upstream fix

- Issue: `cimd-allow-private-use-addresses` (keycloak#53812) is slated for 27.0.0; a realm could then set it on, and on 26.8.1 the key is unknown.
- Options: A an intent of its own at the upgrade to 27.x: the stack's realms get the setting off, and RQ-17 refuses an export that sets it on; until then nothing / B RQ-17 refuses the key now, whatever its value, if 26.8.1 accepts it at import (a facts check first) / C nothing: the proxy suffices.
- Recommendation: A: the check needs the version that reads it; the proxy holds meanwhile.
- Decides: tech lead
- Decision: to decide

### PA-03: Which fetches are in scope

- Issue: the intent's third question: identity providers' discovery, clients' `jwks_uri`, request objects.
- Options: A everything Keycloak fetches over HTTP from what an unauthenticated client presents (the metadata document and its `jwks_uri`, `sector_identifier_uri`, `request_uris`; a `request_uri` parameter), each proven by a test; realm-authored URLs out of scope (Out of scope) / B the metadata document only.
- Recommendation: A: under PA-01 A it comes with the proxy, and only the tests are added; realm-authored URLs come from a trusted author and some name internal hosts on purpose.
- Decides: tech lead
- Decision: to decide

### PA-04: The published image and the applications' tests

- Issue: under PA-01 A the refusal lives in the stack, not in the image: an application's tests that start `KC_PUBLISHED_IMAGE` alone (poc-immo-pf's `CimdIT`) still see private addresses fetched, and its private-address case stays green.
- Options: A accepted and said in README ("Keycloak in an application's tests"): tests of the image don't inherit the refusal; poc-immo-pf reviews `CimdIT` with this delivery / B the image also carries a default proxy configuration that tests must satisfy (a proxy container in every application's tests).
- Recommendation: A: the exposure is the shared stack's; a test container on a throwaway network exposes nothing.
- Decides: PO
- Decision: to decide

### PA-05: The names Keycloak reaches directly

- Issue: under PA-01 A, the internal destinations of RQ-05 must bypass the proxy, which would refuse them; a trusted domain must never match a bypass.
- Options: A a fixed list derived from RQ-17's shapes: names without a dot, a last label outside the IANA root zone (`host.docker.internal`, `*.gateway`, `*.mcp`), two labels starting with a registered application's name or `c4-infra`, and `INFRA_HOST`; residual: a realm trusting a domain that covers `INFRA_HOST` makes Keycloak fetch from Caddy directly, which serves what it serves to the Internet / B a per-application list written by the registration (exact names only): tighter, one more file to keep in step.
- Recommendation: A: RQ-17 already refuses every one of those shapes as a trusted domain, so bypass and trust stay disjoint; the `INFRA_HOST` residual is a public site reached by another path.
- Decides: tech lead
- Decision: to decide

## Acceptance criteria

The `*-facts.sh` way: a throwaway Keycloak of the stack's image, on a test network, with the proxy and Keycloak options as the stack sets them, a realm trusting `trusted.example`, and a document server that logs each request.

- **AC-01:** Given `trusted.example` resolving to the document server at a `10.x` address of the test network, when an authorization starts with its document URL as `client_id`, then the document server logs no request, the response is no login nor consent page, and the realm holds no such client. (RQ-01, RQ-02)
- **AC-02:** Given `trusted.example` resolving in turn to `127.0.0.1`, `169.254.169.254`, `100.64.0.1`, `fd00::1`, `::1` and `::ffff:10.0.0.1`, when the authorization starts, then the fetch is refused for each (the proxy's refusal logged with the address) and no client is created. (RQ-01)
- **AC-03:** Given a name whose resolver answers a public address, then a private one (TTL 0), when the authorization starts, then no request reaches the private address. (RQ-03)
- **AC-04:** Given a document on an allowed address that answers `302` to a private one, when the authorization starts, then the private address receives no request and no client is created. (RQ-03)
- **AC-05:** Given the document server at an address the test's proxy rules admit explicitly (the stack's rules plus that one address), when the authorization starts, then the document is read and the login page shows. (RQ-04)
- **AC-06:** Given a valid document on an allowed address whose `jwks_uri` (then `request_uris`) points at a private address, when the authorization starts, then that address receives no request. (RQ-06, PA-03)
- **AC-07:** Given the dev stack and the stand-in demo host with this change, when Faito's back-channel logout, a simulated provider's login and a mail are exercised, then each succeeds, and the image's log names exactly the three features. (RQ-05, RQ-07)
- **AC-08:** Given AC-01's test run against the stack's configuration before this change, then it fails: the test guards the change. (RQ-01)
- **AC-09:** Given README, then it names where the refusal lives, the bypassed names and what the published image's tests inherit; `tests/0029-description.sh` passes. (RQ-08)

## Intent questions

- Is a fix in Keycloak itself enough, or does the stack filter either way? → no release fixes it (upstream `f505504307`, 27.0.0, unreleased; check-then-fetch); PA-01, PA-02.
- An outgoing proxy or a network rule? → PA-01 (A proxy recommended; a network rule can't keep RQ-05).
- Other fetching features, in scope? → PA-03.

## Change log

- v1 — 2026-11-01 — first version, left `draft` for the PO's decisions on PA-01 to PA-05
