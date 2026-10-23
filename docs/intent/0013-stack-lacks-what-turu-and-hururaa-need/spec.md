# Spec: The shared stack lacks what Turu and Hurura'a need to move onto it

- Intent: [0013](intent.md)
- Status: approved
- Version: 3
- Risk: high (rules: authentication, Keycloak's version and features shared by every application, one of them experimental; what a host exposes, a new origin per MCP server; tech lead's agreement required)
- Policies applied: none yet; standing constraints: README design, 0003 (routes files, dev and demo alike), 0004 (the registry), 0007 (one network per application), 0009 and 0010 (the master realm's settings), Turu's decision 0011 (agent delegation), the agents' access spec (Jérôme Wacongne, 2026-10-23: MCP server and token exchange, which the applications follow)
- Approved: 2026-10-23, Jérôme Wacongne (product owner, and tech lead for the high risk)

## Summary

The shared Keycloak moves to 26.8.1 with the two preview features Turu's agent delegation needs and the experimental client ID metadata documents (CIMD), in dev and on the demo host, keeping every realm, user and session; the demo's deployment dumps Keycloak's database before a new version first starts. An application's MCP server gets an origin of its own, `<app>-mcp`, as the agents' access spec requires (bearer-only, distinct from the BFF's), served from its routes file in dev and on the demo host. The proxy limits the rate of anonymous client registrations; the registration refuses a realm whose CIMD policy would let Keycloak fetch plain-HTTP or any-domain URLs. The guide, the README and Turu's example routes file state what the migration plans had to correct, and what the shared host offers an MCP client.

## Requirements

- REQ-1 The shared Keycloak runs version 26.8.1, in dev and on the demo host, pinned to that version (today a floating `26.7`). (intent: outcome, a 26.8 realm imports)
- REQ-2 It enables the preview features `token-exchange-delegation` and `parameterized-scopes` (PA-1) and the experimental feature `cimd` (PA-5), and no other. (intent: outcome, delegation; agents' spec phase 2)
- REQ-3 The change keeps the master realm, every application's realm, their users, settings and sessions; Keycloak migrates its database at its first start, once (logins fail during that restart). (intent: outcome, constraint)
- REQ-4 On the demo host, the deployment dumps Keycloak's database into the backups directory before it starts a Keycloak image the host hasn't run yet; a deployment that keeps the image dumps nothing (PA-2). (intent: constraint, no way back but a backup)
- REQ-5 A realm on the shared Keycloak configured for delegation as Turu's is issues a delegated token: its `act.client_id` names the actor. (intent: criterion)
- REQ-6 A realm without a `delegate` permission issues no delegated token; the two scopes the features add to every realm are accepted (PA-1). (intent: open question, constraint)
- REQ-7 An application's MCP server is served on an origin of its own, which the application's cookies (session, `XSRF-TOKEN`, at path `/`) never reach: `https://<app>-mcp.dev.localhost/` in dev, `https://<app>-mcp.c4-soft.com/` on the demo host, the first label of the registry's host names suffixed with `-mcp` (PA-4). The routes of its routes file whose target is `mcp` are served there, and only there; the application's origin no longer serves them. Upstreams: `https://host.docker.internal:p280` in dev, the container `<app>.mcp` on port 9080, on `c4-infra.<app>`, on the demo host. That origin gets the headers every site gets, not the single-page applications'. (intent: outcome, MCP; agents' spec INV-5)
- REQ-8 The migration guide states: the REST API's Keycloak admin client on `https://${cn}/auth` in dev (no port) and `http://keycloak:8080/auth` on the demo host; each organization's `redirectUrl` on the project's new origin; the `openapi` profile's management ports (`p091` / `p191`); TLS in dev with c4-infra's leaf and local CA (`C4_INFRA_CERTS_DIR`, the JDK's trust store, a throwaway pair in CI), as Faito; that `new-realm-ids.sh` breaks a reference from one realm file to another's ids, to rewrite with the printed ids; an MCP server (REQ-7, the forwarded host and scheme, the hosts-file line of a command-line client in dev, the DNS record on the demo host); and per project, Turu's demo with its MCP server and no `/assets/` route, Hurura'a's export step (6), Faito's routes file. (intent: outcome, the guide)
- REQ-9 Turu's example routes file has no `/assets/*` route; Hurura'a's keeps its own. (intent: the guide)
- REQ-10 The README states Keycloak's version and the features enabled and why, the MCP origin (REQ-7) and its upstreams, and what the shared host offers an MCP client (REQ-14). (intent: outcome)
- REQ-11 `register-app.sh` refuses a `--proxy <file>.conf` like any file that isn't a routes file, nothing registered (PA-3). (intent: suggested solution)
- REQ-12 The registry refuses an entry whose application name or host names collide with another entry's MCP origin. (agents' spec; 0004)
- REQ-13 In dev, the local leaf covers the MCP origins. (REQ-7)
- REQ-14 An MCP client finds on the shared host what MCP's authorization asks of the authorization server: each realm's RFC 8414 and OpenID discovery at the issuer host's root, PKCE `S256`, `iss` in the authorization response, the standard token exchange, CIMD for the realms whose client policies opt in (PA-5); a `resource` parameter is ignored without error; resource indicators stay off. (agents' spec REQ-1, § 13)
- REQ-15 On the demo host, an application's container exchanges, through `http://keycloak:8080/auth`, a token issued for `https://<infra host>/auth/realms/<realm>`. (agents' spec phase 5)
- REQ-16 The proxy limits, per client address, the requests to a realm's client registration endpoint (`/auth/realms/<realm>/clients-registrations/…`) to 10 a minute, in dev and on the demo host, answering `429` beyond; no other path is limited (PA-6). (agents' spec § 7.4, § 10)
- REQ-17 The registration refuses, in dev and on the demo host, a realm whose client profiles hold a `client-id-metadata-document` executor that allows the `http` scheme (`cimd-allow-http-scheme`) or permits the domain `*` alone, naming the realm file and the profile; nothing is registered (PA-7). (agents' spec phase 2; 0007)

## Out of scope

- Turu's and Hurura'a's own migrations (their plans), and Tickee's (it needs none of this).
- What an application configures in its realm (MCP clients, business scopes and audiences, lifespans, client and registration policies, events): its realm export, which the registration imports as it is (it only sets the brute-force settings, 0010).
- Exporting Keycloak's events to the shared observability (a realm that enables them keeps them in Keycloak's database).
- A realm's client policies changed after its import (console, admin API): the registration checks what it imports (REQ-17).
- Rate limiting any other path than the registration endpoint (PA-6).
- An MCP server routed through its application's gateway (the agents' spec's fallback).
- Any other preview or experimental feature; a backup command of `c4-app` for the applications' databases; changing `new-realm-ids.sh` (its mapping per file separates realms made from one template).

## Design

### Current behaviour

- `keycloak/Dockerfile:2-4`: `FROM quay.io/keycloak/keycloak:${KC_VERSION}`, `KC_VERSION=26.7` (floating; 26.7.4 today), no `KC_FEATURES`. The demo host's image is tagged by `keycloak/`'s content: a change there restarts the demo's Keycloak once. `demo/backup.sh` dumps Keycloak's database nightly (03:15).
- README design: "One origin per application", with `/mcp` among its paths, and its cookies (session, `XSRF-TOKEN`) at path `/`: a browser sends the gateway's session cookie with any request to `/mcp`. The dev leaf covers `*.dev.localhost` (`certs/make-certs.sh:58-60`). Caddy sets `X-Forwarded-*` and streams `text/event-stream` unbuffered (`caddy/Caddyfile:5-6`), and serves each realm's RFC 8414 and OpenID discovery on the issuer host's root (`:44-50`).
- `registry.sh` refuses the `mcp` role's demo upstream, and the tests assert it (`tests/0004-registry.sh:138-139`, `tests/0003-routes.sh:168`, `tests/0003-demo-deploy.stand-in.sh`). Turu's MCP server listens on 9080, management 9081.
- Measured in throwaway containers (`start-dev`), Turu's `keycloak/check-agent-delegation.sh` pointed at them:

  | Case | Result |
  | --- | --- |
  | 26.8.1, no feature, Turu's realm (exported from 26.8.1) | imported; agent login refused, `Invalid scopes: openid delegation:client:turu-agent-dev-actor` |
  | 26.8.1 with the two features (stock image, nothing of Turu's) | `Preview features enabled: parameterized-scopes:v1, token-exchange-delegation:v1`; 13 checks `ok`, `VERIFY OK` |
  | 26.7.4 data (realm, user, live session) started by 26.8.1 with the features | `Migrating older model to 26.8.0`, realms `master` and `existing` migrated, the user's session still listed |
  | Any realm, with the features (`master` included) | client scopes `delegation:client` and `delegation:user` in the realm's default optional scopes: new clients get them, existing clients don't; `adminPermissionsEnabled` false in a new realm |
  | 26.8.1's features | `TOKEN_EXCHANGE_STANDARD_V2` and `ADMIN_FINE_GRAINED_AUTHZ_V2` on by default; `CIMD` and `RESOURCE_INDICATORS` experimental, off; client-policy executors `pkce-enforcer`, `secure-redirect-uris-enforcer`, `use-lightweight-access-token`, `downscope-assertion-grant-enforcer`, `may-act` available |
  | Discovery, authorization request | `authorization_response_iss_parameter_supported: true`, no CIMD field; with `resource=https://…/mcp`: the login page (`200`) |
  | Anonymous client registration, a realm's defaults | refused: `Policy 'Trusted Hosts' rejected request…` (`403`) |
  | 26.8.1 with `cimd` too | `Experimental features enabled: cimd:v1`; every realm's discovery says `client_id_metadata_document_supported: true`; with no client policy, a URL `client_id` (http or https, internal or public) gets `client_not_found` and nothing is fetched; a realm opts in with the condition `client-id-uri` and the executor `client-id-metadata-document`, which exist only with the feature: https only unless `cimd-allow-http-scheme` ("must be OFF in production"), and only the domains of `cimd-allow-permitted-domains` (empty: none; wildcards such as `*.example.org`) |

- `docs/migration.md`: `:64-65` ("unchanged in value"), `:53` (server port only), `:229` (Turu's "uncommitted work"), `:250` ("step 5"), `:235-237` and `examples/routes/turu.routes` (`/assets/`), `:269-273` (Faito's `.conf`); nothing on organizations, certificates or cross-realm ids. `register-app.sh:186-197`: the `.conf` transition, "to remove once Faito 0021 is delivered"; Faito passes `reverse-proxy/faito.routes` (Faito `4a1411b`).

### Behaviour per persona

- Application: Turu's delegation works as in its own Keycloak; its MCP server answers on its MCP origin, in dev and on the demo host, and its exchange goes through Keycloak's back channel. An application whose MCP clients register by CIMD opts in with its realm's client policies (https, named domains); since every realm's discovery advertises CIMD, an MCP client that isn't pre-registered tries it first. Faito and Tickee: nothing to change.
- Developer: `up.sh` rebuilds Keycloak and the proxy once, sessions kept; a command-line MCP client needs a hosts-file line for the MCP origin.
- Demo operator: a DNS record per MCP origin; the deployment that brings this change dumps Keycloak's database, then restarts it once.
- Demo visitor and an agent's user: logins fail for the minute of that restart; an agent's host reaches the MCP origin, never the application's cookies; an address registering more than 10 clients a minute gets `429`.

### API and contracts

- Image: Keycloak `26.8.1` (the tag, which a rebuild refreshes with its base image's fixes; alternative, a digest: reproducible, but no fix without an edit), `KC_FEATURES=token-exchange-delegation,parameterized-scopes,cimd`.
- Proxy: a Caddy image with a rate-limit module (the stock image has none), in dev and on the demo host.
- Routes file: unchanged notation; the lines whose target is `mcp` form the MCP origin's site, `<app>-mcp.<domain of the registry's host>`. Demo upstreams: `gateway` `http://<app>.gateway:7080`, `mcp` `http://<app>.mcp:9080`, `fr`/`en`/`ui` `http://<app>.frontend:80`.
- Registration refusal (REQ-17): `<realm file>: client profile '<name>': the client-id-metadata-document executor allows http (or the domain '*'): Keycloak would fetch any URL, other applications' containers included: refused`.

### User interface

None.

### Data

Keycloak's database, migrated in place to 26.8; its dump before the first start of a new image (demo host).

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| README design: one origin per application | amended: plus one for its MCP server (REQ-7, PA-4) |
| 0003: one routes file, dev and demo alike | REQ-7: the `mcp` lines, in both |
| 0004: the registry refuses collisions | REQ-12 |
| 0007: one network per application | REQ-7: `<app>.mcp` on `c4-infra.<app>` |
| 0009, 0010: the master realm's settings | REQ-3; it gains PA-1's two scopes |
| Turu 0011: delegation in preview, checked at each Keycloak upgrade | REQ-5 |
| Agents' access spec: INV-5 (bearer-only, distinct origin), REQ-1 (MCP authorization), phase 2 (CIMD), phase 5 (exchange), § 7.4 and § 10 (registration, its rate) | REQ-7, REQ-14, REQ-15, REQ-16, REQ-17 |
| 0007: an application reaches none of the others | REQ-17: Keycloak, on every application's network, fetches no URL an application's realm opens to `http` or to any domain |

## Points of attention

### PA-1 Preview features for every application

- Issue: Keycloak supports no preview feature in production, and their shape may change at each upgrade (Turu 0011). Every realm, `master` included, gains the two `delegation:*` scopes, offered to its new clients; the exchange stays refused without a `delegate` permission.
- Options: A enable both, server-wide, accepted knowingly / B also remove the two scopes from the realms that don't use them / C no feature
- Recommendation: A.
- Decides: product owner and tech lead
- Decision: A, both enabled server-wide, accepted knowingly (Jérôme Wacongne, product owner and tech lead, 2026-10-23)

### PA-2 A dump before the demo's Keycloak migrates

- Issue: no way back from 26.8 but a restore; the nightly dump may be a day old.
- Options: A the demo operator, by hand / B the deployment, before starting a Keycloak image it hasn't run yet / C the nightly dump
- Recommendation: B.
- Decides: product owner
- Decision: B, REQ-4 (Jérôme Wacongne, product owner, 2026-10-23)

### PA-3 The `.conf` transition

- Issue: Faito 0021 is delivered; the transition keeps a path no project uses.
- Options: A removed / B kept
- Recommendation: A.
- Decides: tech lead
- Decision: A, REQ-11 (Jérôme Wacongne, tech lead, 2026-10-23)

### PA-4 The MCP origin's name

- Issue: the agents' access spec wants the MCP endpoint on an origin distinct from the BFF's (INV-5). Each needs a name, in dev and on the demo host, which the users give their agents.
- Options: A `<app>-mcp.dev.localhost`, `<app>-mcp.c4-soft.com`: derived from the registry's host names, no new column; the dev leaf's `*.dev.localhost` covers it; one DNS record per application / B `mcp.<app>.dev.localhost`, `mcp.<app>.c4-soft.com`: the dev leaf needs a name per application (a second-level wildcard isn't covered); one DNS record / C no origin of its own: `/mcp` on the application's origin, as today, INV-5 resting on the MCP server ignoring the cookies it receives
- Recommendation: A: the separation INV-5 asks for, at the lowest cost (no certificate, no registry format change).
- Decides: product owner and tech lead
- Decision: A, `<app>-mcp.dev.localhost` and `<app>-mcp.c4-soft.com`; REQ-7 (Jérôme Wacongne, product owner and tech lead, 2026-10-23)

### PA-5 Experimental features for MCP clients

- Issue: CIMD (the registration MCP 2025-11-25 prefers) and resource indicators (RFC 8707) are experimental in 26.8.1, off. The agents' spec falls back to dynamic registration and pre-registered clients, and Keycloak ignores `resource` (measured).
- Options: A neither, reconsidered at each Keycloak upgrade / B CIMD enabled for every realm
- Recommendation: A: an experimental feature has no place on a host serving the public, and the fallback is the agents' spec's own.
- Decides: product owner and tech lead
- Decision: B, `cimd` enabled for the whole server, against the recommendation, accepted knowingly; resource indicators stay off. Measured afterwards: a realm opts in through its client policies, which PA-7 guards; REQ-2, REQ-14 (Jérôme Wacongne, product owner and tech lead, 2026-10-23)

### PA-6 Anonymous client registration on the shared Keycloak

- Issue: a realm that opens anonymous registration (agents' spec § 7.4) lets anyone create clients in it, in the database every application shares; its own policies bound the number and the content (max clients, trusted hosts, allowed scopes, consent), nothing bounds the request rate (§ 10's rate limiting).
- Options: A allowed, bounded by the realm's policies; rate limiting of the shared Keycloak's public endpoints (login, token, registration) at the proxy in a c4-infra intent of its own / B rate limiting in this spec (a Caddy built with a rate-limit module) / C refused: the registration rejects a realm whose anonymous registration is open; MCP clients pre-registered only
- Recommendation: A: the realm's policies bound what lands in the database; rate limiting concerns every public endpoint, login included, and changes how Caddy is built.
- Decides: product owner
- Decision: B, in this spec, for the registration endpoint only (10 a minute per client address); REQ-16 (Jérôme Wacongne, product owner, 2026-10-23)

### PA-7 What a realm's CIMD policy may let Keycloak fetch

- Issue: with `cimd` on (PA-5), a realm's client policy may allow the `http` scheme and the domain `*`: Keycloak would then fetch any URL an unauthenticated client names, on every application's network it is attached to (0007), other applications' containers included.
- Options: A the registration refuses a realm whose `client-id-metadata-document` executor allows `http` or the domain `*` alone, in dev and on the demo host: https to named domains only, Keycloak's defaults / B no check: an application's realm policies are its own (as 0011's leaked deployment key)
- Recommendation: A.
- Decides: product owner and tech lead
- Decision: A; REQ-17 (Jérôme Wacongne, product owner and tech lead, 2026-10-23)

## Acceptance criteria

- AC-1 Given the dev stack rebuilt, and the stand-in demo host deployed, when Keycloak has started, then its log names 26.8.1, exactly the two preview features and, as experimental, `cimd` alone. (REQ-1, REQ-2)
- AC-2 Given a stack on 26.7 with an application's realm, a user and a live session, when it moves to this change (dev: `up.sh`; stand-in: a deployment), then the realm, the user and the session are kept (its refresh token still refreshes), and the master realm keeps 0009's and 0010's settings. (REQ-3)
- AC-3 Given a realm registered on the shared Keycloak with a login client asking `delegation:client:<actor>` and an actor holding a `delegate` permission, when the actor exchanges the agent's token, then the token's `act.client_id` names the actor; without the scope, refused. (REQ-5)
- AC-4 Given a realm without a `delegate` permission, when a client's token carrying `delegation:client:<x>` is exchanged by `<x>`, then refused. (REQ-6)
- AC-5 Given Turu's example routes file, when generated for dev and for the demo host, then `/mcp` and `/.well-known/oauth-protected-resource/mcp` are served on Turu's MCP origin only (to `https://host.docker.internal:11280`, and `http://turu.mcp:9080`), Turu's origin no longer serves them, and it has no `/assets/*` route. (REQ-7, REQ-9)
- AC-6 Given the stand-in demo host and an application with a container `<app>.mcp` answering on 9080, when it registers and starts through `sudo c4-app`, then its MCP origin's `/mcp` reaches it with the public host and scheme (`X-Forwarded-Host`, `X-Forwarded-Proto`), without the single-page applications' headers. (REQ-7)
- AC-7 Given the stand-in demo host on 26.7, when the deployment brings 26.8.1, then a dump taken before Keycloak's restart is in the backups directory; a deployment that keeps Keycloak's image takes none. (REQ-4)
- AC-8 Given `register-app.sh --proxy <file>.conf`, then refused, nothing registered. (REQ-11)
- AC-9 The guide and the README state REQ-8's and REQ-10's points (review). (REQ-8, REQ-10)
- AC-10 Given a registry entry whose name or host name is another entry's MCP origin, when the registry is checked, then refused, naming both lines. (REQ-12)
- AC-11 Given dev's leaf, then it is valid for an application's MCP origin. (REQ-13)
- AC-12 Given a realm on the shared Keycloak, when a client reads `https://<infra host>/.well-known/oauth-authorization-server/auth/realms/<realm>`, then the realm's metadata answers, with `S256`, `authorization_response_iss_parameter_supported` and `client_id_metadata_document_supported`; an authorization request with `resource=` shows the login page. (REQ-14)
- AC-13 Given the stand-in demo host, when a container on `c4-infra.<app>` exchanges, through `http://keycloak:8080/auth`, a token issued for the public issuer, then it gets the exchanged token. (REQ-15)
- AC-14 Given the stack, in dev and on the stand-in demo host, when one address sends more than 10 requests in a minute to a realm's client registration endpoint through the proxy, then the excess gets `429`, while another address, and that address's other requests to Keycloak, are answered. (REQ-16)
- AC-15 Given a realm export whose client profile holds a `client-id-metadata-document` executor with `cimd-allow-http-scheme` on, or with `*` among its permitted domains, when its application registers, then refused naming the file and the profile, nothing registered; with https and `*.example.org`, registered. (REQ-17)
- AC-16 Given the test of AC-15 or AC-5, run on the code before this change, then it fails: the tests guard the change. (REQ-7, REQ-17)

## Intent questions

- Do the two features change anything for the realms that don't use them? → Yes: two optional client scopes in every realm, no delegated token without a `delegate` permission (measured) → PA-1, decided A.
- The version, and how it is pinned? → 26.8.1, the latest 26.8 patch (quay.io, 2026-10-23), pinned by its tag (API and contracts).
- Which container port for an MCP server on the demo host? → 9080, Turu's, as the gateway keeps 7080 (REQ-7).
- *Suggested solution*: drop the `.conf` transition → PA-3, decided A.

## Change log

- v1 — 2026-10-23 — first version
- v2 — 2026-10-23 — PA-1, PA-2 and PA-3 decided (A, B, A); from the agents' access spec (Jérôme Wacongne, 2026-10-23): the MCP server's own origin (REQ-7 rewritten, REQ-12, REQ-13), what the shared host offers an MCP client (REQ-14, REQ-15), PA-4 to PA-6
- v3 — 2026-10-23 — PA-4 A, PA-5 B, PA-6 B decided; CIMD measured (opt-in per realm, its executor's options), hence PA-7, decided A; REQ-2, REQ-7, REQ-14 amended; REQ-16, REQ-17, AC-14 to AC-16 added; approved
