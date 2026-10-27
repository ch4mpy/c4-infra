# Plan: The shared stack lacks what Turu and Hurura'a need to move onto it

- Spec: [v3](spec.md)
- Status: approved
- Branch: 0013-stack-lacks-what-turu-and-hururaa-need
- Approved: 2026-10-23, Jérôme Wacongne (engineer, and tech lead for the high risk)
- Builds on: 0012's branch, merged in at step 0 (then `main`, once 0012 is merged)

## Starting point

- `keycloak/Dockerfile:2-14`: build options before `kc.sh build` (`KC_FEATURES` goes there); `HealthCheck.java` compiled with the image's `jdk.compiler` module (to recheck on 26.8.1).
- Images: Keycloak is `${KC_IMAGE}`, built from `keycloak/` in dev, and on the demo host the workflow's `c4-infra-keycloak:<git tree of keycloak/>` (pushed if missing; `write-env.sh` writes `KC_IMAGE`); the workflow pulls, `demo/deploy.sh` never does and reads no `.env`; the stand-in loads the local image. Caddy is `caddy:2.11.4-alpine` (`compose.yml:41`), pinned by `tests/0003-compose.sh:97` and used to validate the Caddyfile by `tests/0003-caddy-config.sh`, `0003-demo-edge.sh`, `0007-listeners.sh`; the Caddyfile has no global options block (`0003-demo-edge.sh` wraps it in its own).
- `demo/deploy.sh:31`'s `up` replaces a changed Keycloak silently; `demo/backup.sh` dumps through the running `keycloak-db` and deletes `c4-infra-keycloak-db-*.dump` after 7 days.
- `routes.sh`: one site per file; matcher numbers, redirects and "no route" per file; upstreams from `registry_upstream`, which refuses `mcp` on the demo host (`registry.sh:287-290`). `registry.sh`: dotted hosts; one "host name" namespace (`_registry_claim`); `entry`'s output is pinned (`tests/0004-registry.sh:93-116`, the `create-dev-infra` skill).
- `register-app.sh` reads no realm file before importing it and uses no jq; the `.conf` transition is `:186-197`.
- The dev leaf covers `*.dev.localhost` (`certs/make-certs.sh:57-61`). The stand-in serves no HTTPS (ACME blocked): HTTPS behaviour is tested with `0003-demo-edge.sh`'s throwaway Caddy, reachability on the stand-in.
- caddy-ratelimit has one old tag (`v0.1.0`): pinned by commit `5625512f24f6` (2026-06-12); builder image `caddy:2.11.4-builder-alpine`.

## Files

| File | Change | For |
| --- | --- | --- |
| `keycloak/Dockerfile` | modified: `KC_VERSION=26.8.1`; `ENV KC_FEATURES=token-exchange-delegation,parameterized-scopes,cimd` before `kc.sh build` | RQ-01, RQ-02 |
| `registry.sh` | modified: `REGISTRY_KEYCLOAK_THEMES` checked against 26.8.1's built-in themes; `registry_mcp_host <host>` (`<first label>-mcp.<rest>`); `registry_check` claims each entry's two MCP origins as host names (named "`<app>`'s MCP origin") and refuses an application named `<other>-mcp`; `registry_upstream` demo `mcp` → `http://<app>.mcp:9080`; `entry`'s output unchanged | RQ-07, RQ-12 |
| `routes.sh` | modified: `routes_generate` prints the application's site (every route but `mcp`) and, when it has `mcp` routes, the MCP origin's site, each with its own matchers, redirects and `404`; the MCP origin imports `site` only (no `spa-headers`) | RQ-07 |
| `register-app.sh` | modified: the `.conf` transition and its usage text removed; jq required (a clear message when missing); before any change, each realm file whose client profiles hold a `client-id-metadata-document` executor with `cimd-allow-http-scheme` on, or `*` among `cimd-allow-permitted-domains`, refused naming file and profile | RQ-11, RQ-17 |
| `reverse-proxy/Dockerfile` | new: `xcaddy build --with github.com/mholt/caddy-ratelimit@5625512f24f6` on `caddy:2.11.4-builder-alpine`, the binary copied onto `caddy:2.11.4-alpine` | RQ-16 |
| `compose.yml`, `compose.dev.yml`, `env.sh`, `demo/write-env.sh`, `.github/workflows/deploy-demo.yml` | modified: reverse-proxy `image: ${PROXY_IMAGE}`; dev `build: ./reverse-proxy`, `PROXY_IMAGE=c4-infra/reverse-proxy`; the workflow builds and pushes `c4-infra-reverse-proxy:<git tree of reverse-proxy/>` as it does Keycloak's; `write-env.sh` requires and writes `PROXY_IMAGE` | RQ-16 |
| `caddy/Caddyfile` | modified: inside `handle /auth/*`, a `route` with `rate_limit` (zone on `/auth/realms/*/clients-registrations/*`, key `{remote_host}`, 10 events a minute) before `reverse_proxy keycloak:8080` | RQ-16 |
| `demo/deploy.sh`, `demo/backup.sh`, `up.sh` | modified: when `c4-infra.keycloak` runs another image than `KC_IMAGE`'s, `deploy.sh` starts `keycloak-db`, dumps it (`backup.sh --before-upgrade`: a name outside the nightly retention, kept until removed by hand), stops Keycloak, then `up`; a first deployment or the same image dumps nothing; `up.sh` (dev) builds, then stops Keycloak when its image changed (no dump) | RQ-03, RQ-04 |
| `examples/routes/turu.routes` | modified: no `/assets/*`; its header: the `mcp` routes are served on Turu's MCP origin | RQ-09 |
| `tests/0003-routes.sh`, `tests/0004-registry.sh`, `tests/0003-caddy-config.sh`, `tests/0003-dev-routes.sh`, `tests/0003-demo-edge.sh`, `tests/0003-compose.sh`, `tests/0007-listeners.sh`, `tests/0003-demo-deploy.stand-in.sh`, `tests/lib/stand-in-host.sh` | modified: the MCP origin's site (Turu, dev and demo), the demo `mcp` upstream, collision refusals, Turu in the demo validation and accepted on the stand-in; the built proxy image in place of `caddy:2.11.4-alpine` (not for the echo stand-ins); the stand-in loads `c4-infra/reverse-proxy` and sets `PROXY_IMAGE`; the MCP origin's `X-Forwarded-*` and headers through the throwaway demo Caddy | AC-05, AC-06, AC-10 |
| `tests/0013-keycloak.sh` | new (dev): Keycloak's log names 26.8.1, the two preview features and `cimd` as the only experimental one; a realm's RFC 8414 metadata on the issuer host's root with `S256`, `authorization_response_iss_parameter_supported`, `client_id_metadata_document_supported`; `resource=` → the login page; the leaf valid for `faito-mcp.dev.localhost` | AC-01, AC-11, AC-12 |
| `tests/0013-delegation.sh`, `tests/fixtures/0013/verif-delegation-realm.json` | new: a realm derived once from Turu's export (realm settings with FGAP v2, an agent, an actor, an API and an MCP client renamed `verif-*`, the `delegation:*` scopes, the `delegate` permission, one user, no organization), new ids (`new-realm-ids.sh`); Turu's checks 1–4 against it on the dev stack; an exchange by a client without the permission refused | AC-03, AC-04 |
| `tests/0013-rate-limit.sh` | new (dev): 11 requests to a realm's registration endpoint from the host → the 11th `429`, the same address's request to `/auth/realms/master` answered; from a container on `c4-infra`, not `429` | AC-14 |
| `tests/0013-register.sh` | new: stubbed docker: CIMD with `http` or `*` refused before any docker call; https and `*.example.org` pass the check; `--proxy <file>.conf` refused, nothing registered | AC-08, AC-15 |
| `tests/0013-upgrade.stand-in.sh` | new: the stand-in deployed from `origin/main`'s files with its Keycloak image (`c4-infra/keycloak:before`), a realm, a user and a session made; then deployed from the branch: a dump taken before Keycloak's restart, Keycloak stopped before the new import, realm, user and session kept (the refresh token refreshes), master's 0009/0010 settings; a second deployment dumps nothing; the log names 26.8.1 and the features | AC-01, AC-02, AC-07 |
| `tests/0013-mcp.stand-in.sh` | new: Faito with a `faito.mcp` container (Caddy echoing on 9080) and `mcp` routes, through `sudo c4-app`: registered and started, Caddy reaches `faito.mcp:9080`; a token issued through `http://keycloak:8080/auth` for the public issuer exchanged there | AC-06, AC-13 |
| `tests/fixtures/0013/**` | new: `registry.txt` (the real entries plus `31 verif-delegation verif-delegation,verif-cimd-http,verif-cimd-any,verif-cimd-ok - - verif-delegation.dev.localhost verif-delegation.c4-soft.com`), the realms, Faito with its MCP container | AC-03–AC-15 |
| `README.md`, `docs/migration.md`, `docs/demo-setup.md`, `CLAUDE.md` | modified: Design (an application's origin and its MCP origin; Keycloak 26.8.1, its features and why), prerequisites (jq), Routes file (roles table, MCP origin), What an application's deployment does (`<app>.mcp:9080`), realm checks (CIMD), Backups (the pre-upgrade dump); the guide's points of RQ-08; a DNS record per MCP origin; the images the workflow builds; `reverse-proxy/` in the layout | RQ-08, RQ-10, AC-09 |
| `docs/intent/0013-…/plan.md`, `intent.md`, `docs/intent/README.md` | this plan, status planned, index row | — |

## Order of work

0. **Setup**, once 0012 is verified: the scratch worktree removed, `git switch 0013-…`, `git merge 0012-themes-read-keycloak-environment` (and `origin/main`). — skill: none — check: `git status --short` empty, `bash tests/run.sh` → `verification passed`.
1. **Facts**: `tests/0013-keycloak-facts.sh` (throwaway 26.8.1 with the features): its built-in themes, `HealthCheck.java` compiles, the export format of a CIMD executor's configuration; the built proxy lists `http.handlers.rate_limit`. — skill: none — check: the test passes; a failing fact is a deviation before its step.
2. **Keycloak 26.8.1** and its features, the built-in themes, `up.sh` stopping Keycloak on an image change; `tests/0013-keycloak.sh`, the delegation fixture and `tests/0013-delegation.sh`. — skill: none — check: `bash up.sh`, both tests, `bash tests/0009-master-realm.sh && bash tests/0010-brute-force.sh && bash tests/0012-themes.sh`; Faito still logged in (manual).
3. **The proxy image and the rate limit**, the tests that validate the Caddyfile. — skill: none — check: `bash up.sh`, `bash tests/0013-rate-limit.sh && bash tests/0003-caddy-config.sh && bash tests/0003-demo-edge.sh && bash tests/0003-compose.sh && bash tests/0007-listeners.sh`.
4. **The MCP origin**: `registry.sh`, `routes.sh`, Turu's example, their tests. — skill: none — check: `bash tests/0003-routes.sh && bash tests/0004-registry.sh && bash tests/0003-caddy-config.sh && bash tests/0003-dev-routes.sh`.
5. **`register-app.sh`**: no `.conf`, jq, the CIMD refusal. — skill: none — check: `bash tests/0013-register.sh && bash tests/0002-register-scope.sh`.
6. **The demo host**: `deploy.sh`, `backup.sh`, the workflow, `write-env.sh`, the stand-in helpers, the stand-in tests. — skill: none — check: `bash tests/0013-upgrade.stand-in.sh && bash tests/0013-mcp.stand-in.sh && bash tests/0003-demo-deploy.stand-in.sh`.
7. **Docs**. — skill: none — check: review against AC-09 and RQ-08's list.
8. **Verification**: `bash tests/run.sh --all`; mutation checks (AC-16): `routes.sh` and `registry.sh` from 0012's head → `tests/0003-routes.sh`'s MCP origin checks `KO`; `register-app.sh` from 0012's head → `tests/0013-register.sh`'s CIMD checks `KO`; then `/sdlc-verify 0013`. — skill: sdlc-verify — check: `verification passed`.
9. **After the merge** (the human's): the workflow pushes both images, the deployment dumps, stops and upgrades Keycloak. — skill: sdlc-ship — check, on `infra.c4-soft.com`: Keycloak's log line (26.8.1, the features), a realm's RFC 8414 metadata with `client_id_metadata_document_supported`, the 11th registration request `429`, the master realm and its settings unchanged, the dump in `~c4-infra/backups`.

## Risks

- `HealthCheck.java` no longer compiles on 26.8.1 → step 1; fallback: compiled in a JDK build stage.
- An upgrade running the new import (0012) and migration while the old Keycloak runs → Keycloak stopped first, in `deploy.sh` and `up.sh`; proven by `tests/0013-upgrade.stand-in.sh`.
- The pre-upgrade dump deleted by the nightly retention → a name of its own, kept until removed by hand (README).
- `rate_limit`'s order → inside a `route`, as written, with no global option (`0003-demo-edge.sh` wraps the Caddyfile); `caddy validate` and `tests/0013-rate-limit.sh`.
- Every dev client has Docker Desktop's address → AC-14's other address is a container on `c4-infra`. The applications' containers reach `keycloak:8080` without the proxy → the limit concerns the public endpoint (spec), the README says so.
- The delegation fixture's FGAP v2 references broken by the trimming → Turu's checks run against it; new ids so it never clashes with Turu's realm.
- No HTTPS on the stand-in → HTTPS and headers through `0003-demo-edge.sh`'s throwaway Caddy; the stand-in proves acceptance and reachability.
- An upgrade can't be undone on the demo host → the dump (RQ-04) and the README's restore procedure.
- 0011 changes the same scripts afterwards → its plan merges this branch.

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| AC-01 | automated tests | `tests/0013-keycloak.sh` (dev), `tests/0013-upgrade.stand-in.sh` (demo): 26.8.1, the two preview features, `cimd` alone experimental |
| AC-02 | automated test (stand-in) + manual check | `tests/0013-upgrade.stand-in.sh`: realm, user, session (refresh) and master's settings kept from 26.7; dev: Faito still logged in after `up.sh` (step 2) |
| AC-03 | automated test | `tests/0013-delegation.sh`: `act.client_id` names the actor; without the scope, refused |
| AC-04 | automated test | `tests/0013-delegation.sh`: an exchange by a client without a `delegate` permission refused |
| AC-05 | automated test | `tests/0003-routes.sh`: Turu's `mcp` routes on `turu-mcp.*` only, to `https://host.docker.internal:11280` and `http://turu.mcp:9080`; no `/assets/*` |
| AC-06 | automated tests | `tests/0013-mcp.stand-in.sh` (accepted, `faito.mcp:9080` reached), `tests/0003-demo-edge.sh` (the MCP origin's `X-Forwarded-Host`/`-Proto`, no `spa-headers`) |
| AC-07 | automated test (stand-in) | `tests/0013-upgrade.stand-in.sh`: a dump before Keycloak's restart; none when the image stays |
| AC-08 | automated test | `tests/0013-register.sh`: `--proxy <file>.conf` refused, nothing registered |
| AC-09 | review | README and `docs/migration.md` against RQ-08 and RQ-10 |
| AC-10 | automated test | `tests/0004-registry.sh`: an entry on another's MCP origin, or named `<app>-mcp`, refused naming both lines |
| AC-11 | automated test | `tests/0013-keycloak.sh`: `openssl x509 -checkhost faito-mcp.dev.localhost` on the leaf |
| AC-12 | automated test | `tests/0013-keycloak.sh`: the RFC 8414 metadata fields; `resource=` → the login page |
| AC-13 | automated test (stand-in) | `tests/0013-mcp.stand-in.sh`: the exchange through `http://keycloak:8080/auth` |
| AC-14 | automated test (dev) + after deployment | `tests/0013-rate-limit.sh`; step 9 on `infra.c4-soft.com` |
| AC-15 | automated test | `tests/0013-register.sh`: `http` and `*` refused, https and `*.example.org` pass |
| AC-16 | mutation check | step 8: `tests/0003-routes.sh` and `tests/0013-register.sh` `KO` on 0012's head |

## Deviations

<!-- filled during implementation: date — what — why — impact on files or proof -->

- 2026-10-24 — order and place: step 4 (the MCP origin) first, then steps 2, 3, 5 and 6's files, in a scratch worktree while 0012's full suite ran in `D:\workspaces\c4-infra`; the steps that need the dev stack on Keycloak 26.8.1 (`up.sh`, `tests/0013-keycloak.sh`, `-delegation.sh`, `-rate-limit.sh`) run in the main tree once 0012 is delivered, the dev database dumped first. Step 1's facts (`tests/0013-keycloak-facts.sh`, 19 checks) ran before any of them: 26.8.1's built-in themes are 26.7's (`base keycloak keycloak.v2 keycloak.v3`: `REGISTRY_KEYCLOAK_THEMES` unchanged), `HealthCheck.java` compiles, the proxy lists `http.handlers.rate_limit`.
- 2026-10-24 — CIMD measured (facts (c) to (e), a throwaway 26.8.1 and its bytecode): Keycloak reads `cimd-allow-http-scheme` as Jackson does (`"true"`, `"TRUE"`, `" true"`, `1` are true: fetched over http); a permitted domain `*` matches no host (it compares the host to the domain, or to the suffix after `*.`), while `*.` matches every host written with a final dot (`https://any.example./` fetched), which is any domain; a domain list written as a string is refused at import. — `register-app.sh` refuses a CIMD executor whose http setting isn't `false` (or absent) and the domains `*` (PA-07's decision) and `*.` (the "any domain" PA-07 meant; confirmed by the product owner, Jérôme Wacongne, 2026-10-24); the `"##"`-joined form left the check; `tests/0013-register.sh`'s cases follow; README's realm rule.
- 2026-10-24 — `register-app.sh` gives jq the realm file on its stdin: it exports `MSYS_NO_PATHCONV=1`, which left jq (a Windows program under Git Bash) a Git Bash path it can't open, so every absolute `--realm` path was refused as "not JSON" on the workstation. `tests/0013-register.sh` writes its realms under `/tmp` (absolute), which shows it.
- 2026-10-24 — `keycloak-import` migrates the database (`--spi-connections-jpa--quarkus--migration-strategy=update`): `tests/0013-upgrade.stand-in.sh` showed 26.8.1's import exiting 1 on 26.7's database ("Database not up-to-date, please enable database migration": an import validates the schema, it doesn't migrate it), which failed the upgrade, in dev as on the demo host. Measured again by hand on PostgreSQL ("Migrating older model to 26.8.0", exit 0), then by the stand-in test (29 checks: the dump before Keycloak's stop, its stop before the new import, the realm, the user, the session and the master realm kept, no dump the second time). `compose.yml`, README "Backups" (and the way back: the dump restored, Keycloak stopped, before the previous version is deployed).
- 2026-10-24 — `tests/0013-upgrade.stand-in.sh` upgrades from a fixed commit, 0012's head `e493826` (Keycloak 26.7 and keycloak-import, what the demo host runs before 0013), not `origin/main`: it keeps upgrading once 0013 is merged.
- 2026-10-24 — the delegation fixture keeps Turu's client ids (`turu-*`): its FGAP v2 permission and its `delegation:client:<actor>` scopes name them, and renaming them is the reference rewriting the plan's risk named; the realm's name (`verif-delegation`) and new ids keep it apart from Turu's.
- 2026-10-24 — `tests/0013-mcp.stand-in.sh` deploys Turu (registry entry 1, realm `turu`: `tests/fixtures/0013/turu/`), the application with an MCP server, rather than Faito: `turu.mcp` on 9080 through `sudo c4-app`; AC-13 with a realm of two clients (a standard exchange, from `turu.mcp`, through `http://keycloak:8080/auth`, of a token issued for `https://infra.c4-soft.com/auth/realms/turu`). The MCP origin's headers (AC-06) through `tests/0003-demo-edge.sh`'s throwaway Caddy and an echo of its own (`tests/fixtures/0013/forwarded-upstream.caddy`); `tests/0003-dev-routes.sh` serves `turu-mcp.dev.localhost` to an echo on 11280.
- 2026-10-24 — `docs/migration.md` also drops what had gone stale: Turu's "uncommitted work" note, Hurura'a's export step (6, not 5), Faito's `.conf` transition.
- 2026-10-24 — step 8's first run of the suite on 26.8.1 and the built proxy (`0c84893`): 16 `KO` in tests outside *Files*, none in 0013's own. Causes and fixes: `demo/write-env.sh` now requires `PROXY_IMAGE`, which three tests' calls didn't pass (`tests/0009-master-realm.sh`, the `rewrite_env` of `tests/0006-bootstrap-admin-replaced.stand-in.sh` and `tests/0009-master-realm.stand-in.sh`); `tests/0005-themes.sh` expected the stock `caddy:` image name (now `c4-infra/reverse-proxy`); `tests/0003-up-reload.sh` took any mention of `c4-infra.keycloak` in the fake docker's log as the registration account running after a refused reload, which `up.sh`'s new `docker inspect` of Keycloak's image (before the reload) now trips: the check names `docker exec` of that container, the admin CLI's call. Keycloak 26.8.1 changes fact (g) of `tests/0009-master-import-facts.sh`: a login refused for an unverified address stores no `VERIFY_EMAIL` required action (26.7 did, and kept it once the address was verified, until removed by hand): measured on a throwaway (`actions: []` after the refusal; the login works once verified); the facts test records 26.8.1's behaviour, and `registration-account.sh`'s message no longer tells to remove an action that isn't there (verify the address instead). Two runs of mine overlapped another session's work on the same Docker (an image rebuilt and pruned under the running proxy): the first run's `0005` KO had that cause too; the suite runs again, alone.
- 2026-10-27 — the intent home's index, before the verification: the duplicate 0012 row ("planned", left by a merge) removed, 0011's row set to its intent's status ("planned", decided 2026-10-23); a coherence pass of the plans of 0011, 0013, 0015 and 0016 found both rows stale on every branch. Merged `origin/main` (`5a23193`: the identifiers on sdlc-spec's default rule, PR #10; two comment conflicts in `tests/0003-demo-edge.sh` and `tests/0003-dev-routes.sh` kept as this branch wrote them). No file outside *Files* beyond the index.
- 2026-10-27 — verification, fix round 1. `register-app.sh` also refuses a realm export holding a realm attribute `client-policies.*` (Keycloak stores the client profiles and policies there, out of the `clientProfiles` check), and, when Caddy refuses a site while the running proxy's image isn't `PROXY_IMAGE`'s, says to run `up.sh` (the deployment on the demo host) instead of blaming the routes file; `tests/0013-register.sh` covers both, the second in a scratch stack with a fake docker of its own (as `tests/0002-register-scope.sh`). AC-04 in `tests/0013-delegation.sh` removes the realm's `delegate` permission and repeats checks 1 and 3's requests (the former case, an exchange by `turu-api` of a token whose `may_act` named another actor, was refused for that mismatch whatever the permission). Measured on 26.8.1: Keycloak checks the permission at the login, which then drops the `delegation:client:<actor>` scope and `may_act`, so the exchange is refused ("Invalid may_act claim"); a token issued with `may_act` before the removal still exchanges afterwards (until it expires). The 0013 tests share `kc_curl`, `kc_claims` and `kc_features` from `tests/lib/keycloak.sh` (outside *Files*), and pass secrets on stdin or in the environment, never on a command line.
- 2026-10-27 — fix round 3 (the verifier): round 1's older-proxy check compared `docker inspect -f '{{.Image}}'` with the tag's `docker image inspect -f '{{.Id}}'`, which differ with Docker Desktop's containerd image store though the proxy runs its tag (measured: `21d40cb…` against `ed1c89f…`): every site Caddy refused would have blamed the image. The check is gone; the refusal names both causes, the routes file and a proxy not restarted since a pull or a rebuild (run `up.sh` first), Caddy's last lines still shown; `tests/0013-register.sh`'s two cases become one. `up.sh`'s Keycloak check compares the same ids: there a mismatch can only stop Keycloak once more than needed, never let an import run under the old version (equal ids for different images don't happen): kept.
- 2026-10-27 — spec v4 (PA-08 A, found by the bug review): `register-app.sh` also refuses a CIMD permitted domain that names no public host (an IP address, a single label, a last label outside the IANA root zone, `<registered application or c4-infra>.<x>`, after a leading `*.`, case ignored, a final dot removed), naming the file, the profile and the domain. Files: `tlds-alpha-by-domain.txt` (new, IANA's list as downloaded, its version line kept) and `demo/deploy-files.txt` (it sends the list to the demo host, where `c4-app` runs `register-app.sh` from the stack's directory), both outside *Files*, and `tests/0002-register-scope.sh`'s scratch stack copies it (its registration with a realm stopped on the missing list); README's realm rule lists the refusals and says the check reads the name, not what it resolves to, and its Keycloak paragraph says when the `delegate` permission is checked (AC-04, decided by the product owner). Proof: AC-15's line also covers `10.0.0.1`, `[::1]`, `keycloak`, `*.mcp`, `faito.gateway`, `host.docker.internal`, `faito.rest-api-db`, `c4-infra.rabbitmq` and `faito.app` refused before any docker call, `turu.c4-soft.com`, `*.xn--p1ai` and `*.example.org` passing; AC-16: `tests/0013-register.sh` on `b250f1d`'s `register-app.sh`, 18 `KO`, all in the new refused cases.
- 2026-10-27 — spec v5: `register-app.sh` also refuses a wildcard over a whole top-level domain (`*.<one label>`: `*.com`, `*.xn--p1ai`, every domain of it), its own reason in the message; a last label outside the IANA root zone is named first (`*.mcp`), the clearer cause. Files: `register-app.sh`, `tests/0013-register.sh`, README's realm rule, no new one. Proof: AC-15's line refuses `*.com` and `*.xn--p1ai` too, its IDN twin is `*.xn--d1acufc.xn--p1ai` (passes, docker called) instead of `*.xn--p1ai`; AC-16: `tests/0013-register.sh` on `b250f1d`'s `register-app.sh`, 22 `KO`, all in the refused cases (two per domain), none in the twins.
- 2026-10-27 — spec v4's list `tlds-alpha-by-domain.txt`: `tests/0006-registration-without-bootstrap-password.sh` copies the stack's scripts into a scratch directory without it, and its realm registration stopped (`--all` on 27da175: 2 KO, "tlds-alpha-by-domain.txt is missing"); its copy line gains the list, as `tests/0002-register-scope.sh`'s did; no check changed.

## Verification

<!-- sdlc-verify's evidence block as posted on PR #4 on 2026-10-27, in normal mode (4 review rounds), carried over as is when 0013 went to bootstrap mode -->

### Verification — 509e7fd

- Verification command: `bash tests/run.sh --all` → 39/40 passed on 27da175 (2026-10-27, 15:39–16:34 UTC), the one KO `tests/0006-registration-without-bootstrap-password.sh` (its scratch copy lacked v4's `tlds-alpha-by-domain.txt`), fixed in 509e7fd → `bash tests/0006-registration-without-bootstrap-password.sh` → `every check passed`; earlier full runs: `--all` → `verification passed` on 89f6911, `bash tests/run.sh` → `verification passed` on c15b737
- Risk tier: high (authentication: Keycloak 26.8.1 with preview and experimental features shared by every application; what a host exposes: an MCP origin per application, the registration endpoint's rate limit)
- Spec: v4 and v5 at verification (PA-08 A, approved by Jérôme Wacongne, product owner and tech lead, 2026-10-27): RQ-17 also refuses CIMD domains that name no public host (IP, single label, last label outside the IANA list, a wildcard over a single label, `<app or c4-infra>.<x>`)
- Reviews: 4 rounds
  - round 1: bugs 6 Important (4 fixed, 1 refuted by measurement, 1 → spec v4) and 9 detail (5 fixed, 4 answered); security 2 detail (1 fixed, 1 refuted); quality 6 (5 applied, 1 answered)
  - round 2: 0 Important, 2 detail (answered); round 3 (verifier): 1 bug of round 1's fix, fixed (d3e876c); round 4 (v4/v5 diff): 0 Important, 5 detail, open below
  - rate limit bypass by `;a=1`, `/./`, `x/../`, `//`: refuted, measured through the dev proxy (Keycloak refuses `;`; the others get `429` from the 11th request)
  - kept, with reasons in the plan's *Deviations*: Turu's real port 11280 in `tests/0003-dev-routes.sh`; one rate-limit bucket per workstation in dev; the project's multi-line comments; `up.sh`'s and `deploy.sh`'s different image comparisons (with containerd, `up.sh`'s can only stop Keycloak once more than needed)
- Mutation checks: AC-16: `routes.sh` + `registry.sh` at e493826 → `tests/0003-routes.sh` `13 check(s) failed`; `register-app.sh` at e493826 → `tests/0013-register.sh` `39 check(s) failed`; v4/v5: `register-app.sh` at b250f1d → `tests/0013-register.sh` `22 check(s) failed`
- Verifier (89f6911): 15/16 criteria OK, 0 KO; AC-15 re-proved on v5 by `tests/0013-register.sh` → `every check passed`
- Not verifiable here: AC-02's dev half (the dev stack already runs 26.8.1); AC-14 on `infra.c4-soft.com` (step 9, after the merge)
- Files outside the plan: `tests/fixtures/0003/demo.env` (follows the `write-env.sh` deviation); the rest are in *Deviations*
- Pre-existing (not fixed, out of scope): the dev proxy answers an unregistered host (`nobody.dev.localhost`) with an empty `200` → bug intent suggested

**Open for the next session** (round 4's details, not fixed, no Important)
- A shape check for CIMD domains (`^(\*\.)?[a-z0-9-]+(\.[a-z0-9-]+)*\.?$` after downcasing) would refuse `" faito.app"` (a leading space passes today, harmless only if Keycloak doesn't trim, unmeasured), `**.com`, `a.*.com`, and give `""` its own reason instead of "not JSON".
- Wildcards over multi-label public suffixes and wildcard-DNS services pass (`*.co.uk`, `*.nip.io`, `*.localtest.me`): PA-08's accepted limit; name them in the README or in the PA-08 B intent (an egress filter for Keycloak).
- The check reads the registry at registration: an application registered later doesn't re-check the others' realms.
- The README doesn't say how to refresh `tlds-alpha-by-domain.txt`; a Unicode domain could be told to use its `xn--` form.

| Criterion | Result | Evidence |
| --- | --- | --- |
| AC-01 | OK | `tests/0013-keycloak.sh` → `every check passed` (26.8.1, exact feature lists) |
| AC-02 | OK (stand-in); dev half not verifiable here | `tests/0013-upgrade.stand-in.sh` → `ok - AC-02: the session is kept: its refresh token refreshes ("ok")` |
| AC-03 | OK | `tests/0013-delegation.sh` → `ok - AC-03: its act names the actor` |
| AC-04 | OK | `ok - AC-04: the actor's delegated exchange is refused ("Invalid may_act claim in the subject_token")`; with the permission kept: `3 check(s) failed`; README: `delegate` is checked when a token is issued (product owner, 2026-10-27) |
| AC-05 | OK | `tests/0003-routes.sh` → `every check passed` |
| AC-06 | OK | `tests/0013-mcp.stand-in.sh` → `ok - AC-06: Caddy reaches turu.mcp:9080 (its answer)` |
| AC-07 | OK | `ok - AC-07: dumped before Keycloak stops` |
| AC-08 | OK | `tests/0013-register.sh` (the `.conf` refused, docker never called) |
| AC-09 | OK (review) | `docs/migration.md`, `README.md` |
| AC-10 | OK | `tests/0004-registry.sh` → `every check passed`; demo host by hand: exit 1 naming both lines |
| AC-11 | OK | `ok - AC-11: the dev leaf is valid for faito-mcp.dev.localhost` |
| AC-12 | OK | `ok - AC-12: an authorization request with resource= shows the login page` |
| AC-13 | OK | `ok - AC-13: the exchanged token's issuer is the public one` |
| AC-14 | OK (dev, demo configuration); `infra.c4-soft.com` after the merge | `ok - AC-14: the 11th gets 429 from the proxy (429)` |
| AC-15 | OK (v5) | `tests/0013-register.sh` → `every check passed` |
| AC-16 | OK | mutation checks above |

Next: the round-4 details above (optional), then `/sdlc-review 0013`; delivery order 0013 → 0017 → 0011 → 0015 → 0016.

**Delivery** (bootstrap mode, Jérôme Wacongne, product owner, 2026-10-27)

- Manual proofs: AC-02's dev half (a session kept across the upgrade of a dev stack at 26.7.5) not done, the product owner's choice; the stand-in proof covers the demo side. AC-14 on `infra.c4-soft.com`: step 9, after the deployment, below.
- No review stage in bootstrap mode: the evidence above stands for `sdlc-verify`'s round. Round 4's four details stay open, none Important.
- Agent configuration: `CLAUDE.md` gains one layout line; the project has no evals.
- Not the first production release: the demo host is not production (product owner).

**After deployment** (run 40561234968 on `6e03af8`, `success`, 2026-10-27)

- AC-14 on `infra.c4-soft.com`: 11 anonymous registrations of realm master within the minute → `403 403 403 403 403 403 403 403 403 403 429`; master's discovery afterwards → `200`.
- RFC 8414: `/.well-known/oauth-authorization-server/auth/realms/master` → `issuer` `https://infra.c4-soft.com/auth/realms/master`, `client_id_metadata_document_supported: true`.
- On the host, by the product owner: Keycloak's start line (26.8.1, the features), master's settings unchanged, the dump in `~c4-infra/backups`: not done yet.
