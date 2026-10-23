# Spec: The shared stack lacks what Turu and Hurura'a need to move onto it

- Intent: [0013](intent.md)
- Status: draft
- Version: 1
- Risk: high (rules: authentication, Keycloak's version and features shared by every application; what a host exposes, a new role routed on the demo host; tech lead's agreement required)
- Policies applied: none yet; standing constraints: README design, 0003 (routes files, dev and demo alike), 0007 (one network per application), 0009 and 0010 (the master realm's settings), Turu's decision 0011 (agent delegation)
- Approved: —

## Summary

The shared Keycloak moves to 26.8.1 with the two preview features Turu's agent delegation needs, in dev and on the demo host, keeping every realm, user and session. On the demo host, an application's routes file may name the `mcp` role, routed to its container `<app>.mcp:9080`. The migration guide, the README and Turu's example routes file state what the three migration plans had to correct.

## Requirements

- REQ-1 The shared Keycloak runs version 26.8.1, in dev and on the demo host, pinned to that version (today a floating `26.7`). (intent: outcome, a 26.8 realm imports)
- REQ-2 It enables the preview features `token-exchange-delegation` and `parameterized-scopes`, and no other. (intent: outcome, delegation)
- REQ-3 The change keeps the master realm, every application's realm, their users, settings and sessions; Keycloak migrates its database at its first start, once (logins fail during that restart). (intent: outcome, constraint)
- REQ-4 On the demo host, a dump of Keycloak's database taken before the new version first starts exists → PA-2. (intent: constraint, no way back but a backup)
- REQ-5 A realm on the shared Keycloak configured for delegation as Turu's is issues a delegated token: its `act.client_id` names the actor. (intent: criterion)
- REQ-6 A realm without a `delegate` permission issues no delegated token; what the features change in the other realms is accepted knowingly → PA-1. (intent: open question, constraint)
- REQ-7 On the demo host, the `mcp` role routes to `http://<app>.mcp:9080`; an application's MCP server runs as container `<app>.mcp`, on its network `c4-infra.<app>`. Dev is unchanged (`https://host.docker.internal:p280`). (intent: outcome, MCP)
- REQ-8 The migration guide states: the REST API's Keycloak admin client on `https://${cn}/auth` in dev (no port) and `http://keycloak:8080/auth` on the demo host; each organization's `redirectUrl` on the project's new origin; the `openapi` profile's management ports (`p091` / `p191`); TLS in dev with c4-infra's leaf and local CA (`C4_INFRA_CERTS_DIR`, the JDK's trust store, a throwaway pair in CI), as Faito; that `new-realm-ids.sh` breaks a reference from one realm file to another's ids, to rewrite with the printed ids; an MCP server on the demo host (REQ-7, the forwarded host and scheme); and per project, Turu's demo with its MCP server and no `/assets/` route, Hurura'a's export step (6), Faito's routes file. (intent: outcome, the guide)
- REQ-9 Turu's example routes file has no `/assets/*` route; Hurura'a's keeps its own. (intent: the guide)
- REQ-10 The README states Keycloak's version, the features enabled and why (Turu's delegation), and the MCP server's container port. (intent: outcome)
- REQ-11 → PA-3: `register-app.sh` no longer turns a `--proxy <file>.conf` into c4-infra's example routes file. (intent: suggested solution)

## Out of scope

- Turu's and Hurura'a's own migrations (their plans), and Tickee's (it needs none of this).
- Any other preview feature; the supported standard token exchange is already on.
- A backup command of `c4-app` for the applications' databases (a separate intent).
- Changing `new-realm-ids.sh`: its mapping per file is what separates realms made from one template (REQ-8 documents the cross references instead).

## Design

### Current behaviour

- `keycloak/Dockerfile:2-4`: `FROM quay.io/keycloak/keycloak:${KC_VERSION}`, `KC_VERSION=26.7` (floating; 26.7.4 today), no `KC_FEATURES`. Its version is written nowhere else. The demo host's image is tagged by `keycloak/`'s content: a change there restarts the demo's Keycloak once, at the deployment that brings it. `demo/backup.sh` dumps Keycloak's database nightly (03:15), restore in the README.
- Measured in throwaway containers (`start-dev`), Turu's `keycloak/check-agent-delegation.sh` pointed at them:

  | Case | Result |
  | --- | --- |
  | 26.8.1, no feature, Turu's realm (exported from 26.8.1) | imported; agent login refused, `Invalid scopes: openid delegation:client:turu-agent-dev-actor` |
  | 26.8.1 with the two features (stock image, nothing of Turu's) | `Preview features enabled: parameterized-scopes:v1, token-exchange-delegation:v1`; 13 checks `ok`, `VERIFY OK` |
  | 26.7.4 data (realm, user, live session) started by 26.8.1 with the features | `Migrating older model to 26.8.0`, realms `master` and `existing` migrated, the user's session still listed |
  | Any realm, with the features (created before or after, `master` included) | client scopes `delegation:client` and `delegation:user` added to the realm's default optional scopes: new clients get them, existing clients don't; the only difference in a realm's discovery document (`scopes_supported`); `adminPermissionsEnabled` stays false in a new realm |

- `registry.sh` refuses the `mcp` role's demo upstream, and the tests assert it (`tests/0004-registry.sh:138-139`, `tests/0003-routes.sh:168`, `tests/0003-demo-deploy.stand-in.sh`); README: "No container port is fixed yet for an MCP server". Turu's MCP server listens on 9080, management 9081 (its `mcp-server/…/application.yml:20`). Caddy's demo site already serves the realms' RFC 8414 discovery (`caddy/Caddyfile:44-50`).
- `docs/migration.md`: `:64-65` ("unchanged in value"), `:53` (server port only), `:229` (Turu's "uncommitted work"), `:250` ("step 5"), `:235-237` and `examples/routes/turu.routes` (`/assets/`), `:269-273` (Faito's `.conf`); nothing on organizations, certificates or cross-realm ids. `register-app.sh:186-197`: the `.conf` transition, "to remove once Faito 0021 is delivered"; Faito's `deploy-dev.sh` passes `reverse-proxy/faito.routes` (Faito `4a1411b`).

### Behaviour per persona

- Application: Turu registers its realm and its delegation works as in its own Keycloak; Turu's demo routes `/mcp` and `/.well-known/oauth-protected-resource/mcp` to its MCP container. Faito and Tickee: nothing to change; their realms gain two optional scopes no client uses.
- Developer: `up.sh` rebuilds Keycloak once; the sessions survive.
- Demo operator: the deployment that brings this change restarts Keycloak once, after the dump of PA-2.
- Demo visitor: logins fail for the minute of that restart.

### API and contracts

- Image: Keycloak `26.8.1` (the tag, which a rebuild refreshes with its base image's fixes; alternative, a digest: reproducible, but no fix without an edit), `KC_FEATURES=token-exchange-delegation,parameterized-scopes`.
- Routes file roles, demo upstreams: `gateway` `http://<app>.gateway:7080`, `mcp` `http://<app>.mcp:9080`, `fr`/`en`/`ui` `http://<app>.frontend:80`.

### User interface

None.

### Data

Keycloak's database, migrated in place to 26.8.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| README design: one Keycloak for every application, its version the stack's | REQ-1, REQ-2, REQ-10 |
| 0003: one routes file, dev and demo alike | REQ-7: the `mcp` role in both |
| 0007: one network per application | REQ-7: `<app>.mcp` on `c4-infra.<app>` |
| 0009, 0010: the master realm's settings | REQ-3; it gains PA-1's two scopes |
| Turu 0011: delegation in preview, checked at each Keycloak upgrade | REQ-5; → PA-1 |

## Points of attention

### PA-1 Preview features for every application

- Issue: Keycloak supports no preview feature in production, and their shape may change at each upgrade (Turu 0011). A feature is the server's: every realm, `master` included, gains the two `delegation:*` scopes, offered to its new clients; a client that asks for one gets a `may_act` claim (after consent), while the exchange stays refused without a `delegate` permission.
- Options: A enable both, server-wide, accepted knowingly / B also remove the two scopes from the realms that don't use them, at each registration / C no feature: Turu gives up delegation on the stack (back to its decision 0011's option 1)
- Recommendation: A: measured harmless for realms without a `delegate` permission; B adds a step Keycloak may undo; C reverses Turu's decision.
- Decides: product owner and tech lead
- Decision: to decide

### PA-2 A dump before the demo's Keycloak migrates

- Issue: no way back from 26.8 but a restore; the nightly dump may be a day old.
- Options: A the demo operator runs `demo/backup.sh` on the host before pushing this change (a step in the PR) / B the deployment dumps the database itself before starting a Keycloak image it hasn't run yet, for this upgrade and the next ones / C the nightly dump
- Recommendation: B: Keycloak upgrades recur, and the deployment runs unattended on push.
- Decides: product owner
- Decision: to decide

### PA-3 The `.conf` transition

- Issue: Faito 0021 is delivered; the transition only keeps a path no project uses.
- Options: A removed: a `.conf` is refused like any file that isn't a routes file / B kept
- Recommendation: A: 0003 planned its removal for this moment.
- Decides: tech lead
- Decision: to decide

## Acceptance criteria

- AC-1 Given the dev stack rebuilt, and the stand-in demo host deployed, when Keycloak has started, then its log names 26.8.1 and exactly the two preview features. (REQ-1, REQ-2)
- AC-2 Given a stack on 26.7 with an application's realm, a user and a live session, when it moves to this change (dev: `up.sh`; stand-in: a deployment), then the realm, the user and the session are kept (its refresh token still refreshes), and the master realm keeps 0009's and 0010's settings. (REQ-3)
- AC-3 Given a realm registered on the shared Keycloak with a login client asking `delegation:client:<actor>` and an actor holding a `delegate` permission, when the actor exchanges the agent's token, then the token's `act.client_id` names the actor; without the scope, refused. (REQ-5)
- AC-4 Given a realm without a `delegate` permission, when a client's token carrying `delegation:client:<x>` is exchanged by `<x>`, then refused. (REQ-6)
- AC-5 Given Turu's example routes file, when generated for the demo host, then `/mcp` and `/.well-known/oauth-protected-resource/mcp` go to `http://turu.mcp:9080`, nothing refused; dev's still go to `https://host.docker.internal:11280`. (REQ-7, REQ-9)
- AC-6 Given the stand-in demo host and an application with a container `<app>.mcp` answering on 9080, when it registers and starts through `sudo c4-app`, then `https://<demo host>/mcp` reaches it with the public host and scheme (`X-Forwarded-Host`, `X-Forwarded-Proto`). (REQ-7)
- AC-7 (PA-2 B) Given the stand-in demo host on 26.7, when the deployment brings 26.8.1, then a dump taken before Keycloak's restart is in the backups directory; a deployment that keeps Keycloak's image takes none. (REQ-4)
- AC-8 (PA-3 A) Given `register-app.sh --proxy <file>.conf`, then refused, nothing registered. (REQ-11)
- AC-9 The guide and the README state REQ-8's and REQ-10's points (review). (REQ-8, REQ-10)

## Intent questions

- Do the two features change anything for the realms that don't use them? → Yes: two optional client scopes in every realm, no delegated token without a `delegate` permission (measured) → PA-1.
- The version, and how it is pinned? → 26.8.1, the latest 26.8 patch (quay.io, 2026-10-23), pinned by its tag (API and contracts).
- Which container port for an MCP server on the demo host? → 9080, Turu's, as the gateway keeps 7080 (REQ-7).
- *Suggested solution*: drop the `.conf` transition → PA-3.

## Change log

- v1 — 2026-10-23 — first version
