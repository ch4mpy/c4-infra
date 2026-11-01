# Spec: Keycloak fetches a client's metadata document from a private address when a trusted domain resolves to one

- Intent: [0054](intent.md)
- Status: approved
- Version: 3
- Risk: high (two risk rules apply: it touches authentication, an MCP client's registration by its metadata document, and what a host exposes to the network, the internal addresses Keycloak can be made to call). Accepted risk until the upgrade to Keycloak 27.0 (end of January or early February 2027): an unauthenticated client can make Keycloak fetch an address on the host's private networks (RQ-09, PA-01)
- Policies applied: none (the project has no policy yet); standing constraints: README's design, 0007 (an application reaches none of the others), 0013's RQ-17, no `--features` in an application's container
- Approved: 2026-11-01, Jérôme Wacongne (product owner and tech lead, recorded once; every point of attention decided)

## Summary

The shared Keycloak (26.8.1, `cimd`) fetches an MCP client's metadata document from whatever address a trusted domain resolves to, private ones included: 26.8.1's `client-id-metadata-document` executor checks the URL's host name against the trusted domains, never the address it resolves to. The product owner waits for upstream's fix (PA-01 B): no proxy, no network rule, `cimd` stays enabled. Until the upgrade to Keycloak 27.x the stack accepts the risk, and README says so in plain words, on both environments; this intent delivers that. The upgrade's own intent sets `cimd-allow-private-use-addresses` off in the realms and has the registration refuse an export that sets it on (PA-02 A), for the metadata document only (PA-03 B); the other client-presented URLs and DNS rebinding stay a residual risk, followed upstream.

## Requirements

RQ-01 to RQ-06 (v1: the refusal by the stack itself, its scope beyond the document, rebinding, what Keycloak still reaches through it) are withdrawn by PA-01 B and PA-03 B: see "Out of scope and residual risk".

- **RQ-07:** 0013's RQ-17 stays in force, unchanged; the image still enables exactly `token-exchange-delegation`, `parameterized-scopes` and `cimd`, and nothing of `keycloak/` changes. (intent: constraints; PA-01 B)
- **RQ-08:** README's "Keycloak in an application's tests" says that the published image carries no refusal of private addresses: until 27.x nothing refuses them, and from 27.x the refusal is the realm executor's `cimd-allow-private-use-addresses`, which a test has only through its own import of the realm; an application's test of a private-address fetch (poc-immo-pf's `CimdIT`) proves nothing of the stack. (intent: affected users; PA-04 A)
- **RQ-09:** README states the open risk in plain words, where a realm's author and a demo operator read it (beside the `cimd` checks of "What an application provides"): on both environments, dev and the demo host, an unauthenticated client can make Keycloak fetch an address on the host's private networks (the stack's and the applications' containers, the host itself, a cloud metadata endpoint) through a trusted domain that resolves to it; what that exposes (Keycloak's `GET` reaches any HTTP service listening there; the response isn't shown to the client, but its outcome, error or consent screen, tells whether the address answered a valid document); that the product owner accepted it on 2026-11-01, until the upgrade to Keycloak 27.0, whose intent closes it and is to be taken up end of January or early February 2027 (Keycloak 27.0's release is planned for 29 January 2027); and that a realm which opts into `cimd` takes that risk. (PA-01 B, the product owner's decision on the interim)
- **RQ-10:** The note can't outlive its reason: c4-infra's suite fails once the stack's Keycloak is 27.x or later while README still states the accepted risk, naming what the upgrade's intent owes (the setting off, RQ-17's refusal, README's residual risks). (PA-01 B, PA-02 A: the hand-off to the upgrade's intent)

## Out of scope and residual risk

- **The upgrade's own intent** (PA-02 A; the product owner, 2026-11-01), to be taken up end of January or early February 2027, Keycloak 27.0's release being planned for 29 January 2027: at the upgrade to Keycloak 27.x, no realm on the stack fetches a metadata document from a private address (every `client-id-metadata-document` executor keeps `cimd-allow-private-use-addresses` off, 27.x's default); 0013's RQ-17 check refuses an export that sets it to a value Keycloak reads as true (`true`, `"TRUE"`, `1`, as for `cimd-allow-http-scheme`), naming the profile and the setting; a throwaway Keycloak 27 facts test proves the refusal (a trusted domain resolving to a private document server that logs no request, no consent page, no client created; the setting on as the control that reads it); README's accepted-risk note (RQ-09) gives way to the residual risks below. RQ-10 reminds that intent of it.
- The stack's own refusal (v1's RQ-01 to RQ-06): an egress proxy, a network rule, disabling `cimd`, a backported provider: PA-01 B chose none. Keycloak keeps reaching what it calls today (database, mail, the applications' gateways, the simulated and real providers).
- Residual risk, followed upstream (PA-03 B): the other URLs Keycloak fetches from what an unauthenticated client presents, `jwks_uri`, `sector_identifier_uri` and `request_uris` of a metadata document and a `request_uri` parameter (upstream's commit names the first three; what 27.0.0 refuses is read then, not required here); DNS rebinding between upstream's check and the fetch, which resolves again; a redirect to a private address, which Keycloak's outgoing client doesn't follow by default (`allow-redirects` false).
- URLs a realm's author writes in the export (an identity provider's endpoints, a client's back-channel logout or `jwksUrl`): the realm's author is trusted as by 0013, and some name internal hosts on purpose (`host.docker.internal`, `<app>.gateway`).
- The applications' own tests: poc-immo-pf reviews its `CimdIT` private-address case (PA-04 A); c4-infra's part is RQ-08.

## Design

### Current behaviour

- Reproduced by poc-immo-pf 0021's `CimdIT.givenTrustedDomainResolvingToPrivateAddress_whenAuthorize_thenDocumentRead_privateAddressNotRefused` (poc-immo-pf `backend/immo-api/src/test/java/pf/immobilier/it/CimdIT.java`, commit `018886f`): Keycloak from c4-infra's published image, the realm trusting `agent.cimd-test.example`, a Caddy container under that alias at a site-local address; Keycloak reads the document and shows the consent screen.
- Keycloak 26.8.1's executor has no address check, and no setting for one (`AbstractClientIdMetadataDocumentExecutorFactory.java:43-59` at tag `26.8.1`); `verifyClientId`'s comment about loopback and private addresses (`AbstractClientIdMetadataDocumentExecutor.java:544-547`) describes a check its `verifyUri` doesn't make. The fetch goes through `SimpleHttp.create(session)` (`:592`), Keycloak's outgoing HTTP client, `allow-redirects` false by default.
- Upstream: commit `f505504307` ("ssfr check for cimd", 2026-10-13, closes keycloak/keycloak#53812, labelled `release/27.0.0`) adds `cimd-allow-private-use-addresses` (default off): it resolves the hosts of the Client ID URL, `jwks_uri`, `sector_identifier_uri` and `request_uris` and rejects loopback, any-local, link-local, site-local, multicast, `fc00::/7`, `0.0.0.0/8` and `100.64.0.0/10`, even within the trusted domains; on `main` only, not in 26.8.1 nor on `release/26.8`. It checks before the fetch, which resolves again.
- README today (`README.md:221-238`) says the RQ-17 check "reads the domain's name, not what it resolves to: a public name pointed at an internal address passes, and would let Keycloak fetch from it", without the word risk, its acceptance or its end; the stack's version is `KC_VERSION` in `keycloak-image.properties` (26.8.1).
- Docs consulted (v1): keycloak.org's release notes and "Configuring outgoing HTTP requests", Keycloak's source at tag `26.8.1` and `main`; Context7 was unavailable in that session.

### Behaviour per persona

- Demo visitor (through an MCP client): unchanged.
- Application: opting into `cimd` takes the accepted risk, said in README; its tests of the published image inherit no refusal (RQ-08).
- Developer and demo operator: nothing to run; README tells them the risk and its end.

### API and contracts

- RQ-10's failure is a test's failure in `tests/run.sh`, its message naming 0054 and what the upgrade's intent owes.

### Data

None.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| README design: one image, its features only | RQ-07: no feature, no change of `keycloak/` |
| 0007: an application reaches none of the others | Not satisfied for Keycloak's fetch until the upgrade to 27.x, accepted by the product owner (PA-01 B, RQ-09); the upgrade's intent closes it for the metadata document, the residual risks named |
| 0013 RQ-17 | RQ-07: kept; the upgrade's intent extends it |
| No `--features` in an application's container | RQ-07, RQ-08 |

## Points of attention

### PA-01: Where the refusal happens

- Issue: 26.8.1 has no address check; the stack must refuse on its own, now, or wait.
- Options: A an egress forward proxy for Keycloak's outgoing HTTP / B wait for Keycloak 27.0.0 and set `cimd-allow-private-use-addresses` off / C a network rule / D disable `cimd` until upstream ships the check / E a provider JAR backporting upstream's check (v1 gives each one's costs).
- Recommendation: A, B joining it once released.
- Decides: tech lead
- Decision: B, 2026-11-01, Jérôme Wacongne (product owner and tech lead): wait for Keycloak 27.0.0 and set the setting off then; no proxy, no network rule, `cimd` stays enabled. Until 27.0.0, nothing is done and the risk is accepted: the spec and README state it in plain words, on both environments, with what it exposes and the date accepted (RQ-09).

### PA-02: The upstream fix

- Issue: `cimd-allow-private-use-addresses` (keycloak#53812) is slated for 27.0.0; a realm could then set it on, and on 26.8.1 the key is unknown.
- Options: A at the upgrade to 27.x, the stack's realms get the setting off and RQ-17 refuses an export that sets it on; until then nothing / B RQ-17 refuses the key now, whatever its value / C nothing.
- Recommendation: A.
- Decides: tech lead
- Decision: A, 2026-11-01, Jérôme Wacongne: it follows from PA-01 B; implied by that decision, the product owner may revisit it. That work belongs to the Keycloak upgrade's own intent, not to this one (the product owner, 2026-11-01): "Out of scope and residual risk", RQ-10.

### PA-03: Which fetches are in scope

- Issue: the intent's third question: identity providers' discovery, clients' `jwks_uri`, request objects.
- Options: A everything Keycloak fetches over HTTP from what an unauthenticated client presents / B the metadata document only.
- Recommendation: A.
- Decides: tech lead
- Decision: B, 2026-11-01, Jérôme Wacongne: the metadata document only, what the upstream setting covers; the other client-presented URLs (`jwks_uri`, `sector_identifier_uri`, `request_uris`, a `request_uri` parameter) and DNS rebinding between the check and the fetch are recorded as residual risk, followed upstream ("Out of scope and residual risk").

### PA-04: The published image and the applications' tests

- Issue: no refusal lives in the image: an application's tests that start `KC_PUBLISHED_IMAGE` (poc-immo-pf's `CimdIT`) see private addresses fetched.
- Options: A said in README: tests of the image don't inherit any refusal; poc-immo-pf reviews `CimdIT` / B the image carries a default proxy configuration.
- Recommendation: A.
- Decides: PO
- Decision: A, 2026-11-01, Jérôme Wacongne (RQ-08).

### PA-05: The names Keycloak reaches directly

- Issue: under PA-01 A, the internal destinations Keycloak calls would bypass the proxy.
- Options: A a fixed list derived from RQ-17's shapes / B a per-application list written by the registration.
- Recommendation: A.
- Decides: tech lead
- Decision: A, 2026-11-01, Jérôme Wacongne; moot under PA-01 B: no proxy, no bypass list.

## Acceptance criteria

AC-01 to AC-08 (v1: the stack's refusal, its scope, rebinding, redirects, what Keycloak still reaches) are withdrawn with RQ-01 to RQ-06.

- **AC-09:** Given README's "Keycloak in an application's tests", then it says that the published image carries no refusal of private addresses, that from 27.x the refusal is the realm's setting, and that an application's private-address test proves nothing of the stack; a check of c4-infra's suite reads it. (RQ-08)
- **AC-10:** Given README, then beside the `cimd` checks of "What an application provides" it states the accepted risk: both environments, an unauthenticated client, a trusted domain resolving to an address on the host's private networks, what Keycloak's fetch exposes, accepted on 2026-11-01 until the upgrade to Keycloak 27.0, taken up end of January or early February 2027 (release planned for 29 January 2027); a check of c4-infra's suite reads it. (RQ-09)
- **AC-11:** Given this change, then `keycloak/` and `keycloak-image.properties` are unchanged and `tests/0029-description.sh` passes. (RQ-07)
- **AC-12:** Given a copy of the repository whose `keycloak-image.properties` says `KC_VERSION=27.0.0` and whose README still states the accepted risk, when the check of AC-10 runs, then it fails, naming 0054 and what the upgrade's intent owes; with `26.8.1` it passes. (RQ-10)

## Intent questions

- Is a fix in Keycloak itself enough, or does the stack filter either way? → Keycloak's fix, at 27.0.0, in the upgrade's intent; the stack doesn't filter, the risk accepted until then (PA-01 B).
- An outgoing proxy or a network rule? → neither (PA-01 B).
- Other fetching features, in scope? → no: the metadata document only, the rest residual risk followed upstream (PA-03 B).

## Change log

- v1 — 2026-11-01 — first version, left `draft` for the PO's decisions on PA-01 to PA-05
- v2 — 2026-11-01 — the PO's decisions: PA-01 B (wait for 27.0.0, risk accepted until then), PA-02 A (implied by PA-01 B; its work moves to the Keycloak upgrade's own intent), PA-03 B (the metadata document only, the rest residual risk), PA-04 A, PA-05 A (moot); RQ-01 to RQ-06 and AC-01 to AC-08 withdrawn, RQ-08 rewritten, RQ-09 and RQ-10 added, AC-09 rewritten, AC-10 to AC-12 added; approved
- v3 — 2026-11-01 — the PO's note: the upgrade's intent is taken up end of January or early February 2027 (Keycloak 27.0's release planned for 29 January 2027), the accepted risk lasting until then; the date written in RQ-09, AC-10 and the pointer to the upgrade's intent; approved
