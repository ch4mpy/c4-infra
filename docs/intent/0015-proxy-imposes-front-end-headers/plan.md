# Plan: The shared proxy imposes its security headers on every application's front end

- Spec: [v2](spec.md)
- Status: approved
- Branch: 0015-proxy-imposes-front-end-headers
- Approved: 2026-10-27, Jérôme Wacongne (engineer, and tech lead for the high risk), in plan mode

## Starting point

- Builds on **0013** and **0011**, delivered before it (order decided 2026-10-27: 0013 → 0011 → 0015 → 0016). 0013: it reshapes `routes.sh` (each site written by `_routes_site`, the MCP origin), `caddy/Caddyfile` (the rate limit), the proxy image (`c4-infra/reverse-proxy`, Caddy 2.11.4 with the rate-limit module) and the 0003 tests. 0011: `routes.sh`'s option loop (RQ-11: an option with an empty key refused as unknown, before the `seen_options` lookup, `routes.sh:137-145` on 0013) and `registry.sh`. Step 0 merges `origin/main` once both are delivered, else their branches, 0013's then 0011's; this plan names functions, not lines.
- Measured on 2026-10-27, throwaway `caddy:2.11.4-alpine` containers (removed), upstreams sending some, none, or only `Content-Security-Policy-Report-Only`, a stopped one, `max-body=1KB`:
  - `header { ?A ?B ?C }` in **one block applies all or nothing**: an upstream sending Content-Security-Policy and `X-Frame-Options` didn't get the default `Permissions-Policy`. **One `header ?<field>` directive per field** defaults header by header: sent values kept once, unchanged; missing ones set; a `Report-Only` alone gets the enforced default beside it (RQ-01, RQ-02).
  - A snippet `(spa-header-values)` of `header {args[0]}<field> "<value>"` lines writes the values once: `(spa-headers) { import spa-header-values "" }` sets them as today (a front end's 200: today's duplicates; its `413` and `502`: the three values), `import spa-header-values ?` defaults them. Imported without an argument, `{args[0]}` doesn't vanish and the headers are lost: `spa-headers` always passes `""` (RQ-06).
  - Errors (RQ-02, RQ-08): the proxy's own `413` and `502` lose every deferred header: `common-headers` (deferred by its `-Server`: a gateway `502` carries `Server: Caddy` and only HSTS, a single-line header) and the `?` defaults. One **`handle_errors` in the `site` snippet**, `import common-headers`, then `@app-headers vars app_headers yes` / `handle @app-headers { import spa-header-values ? }`, a `headers=app` route setting the marker `vars app_headers yes`: a gateway `502`, a front end's `413` and `502` (with or without the option) then carry `X-Content-Type-Options`, `Referrer-Policy`, HSTS, no `Server`, and the three values on front-end routes; status, `Content-Length: 0` and empty body unchanged; `respond 404` and the front ends' 200s unchanged.
- No test asserts today's error headers (`git grep` of `413`, `502`, `429`, `Server` in `tests/` on 0013's branch: `tests/0003-dev-routes.sh` checks the `413`'s status, `tests/0013-rate-limit.sh` the `429`'s, the two `no Server` checks are on 200s): AC-05's "the 0003 tests pass unchanged" holds with RQ-08.
- `register-app.sh` generates the site with `routes_generate` before anything changes, and `sudo c4-app register` goes through it on the demo host: a refusal of `routes.sh` is already "nothing registered" (RQ-05) without a change there.

## Engineer's choices

Decided by Jérôme Wacongne (engineer) on 2026-10-27:

- The demo side of AC-01 to AC-04 and AC-08 is proven by a throwaway proxy running `caddy/` with `INFRA_ENV=demo` (as `tests/0003-demo-edge.sh`); the stand-in host proves the registration's refusal only (A).
- No check on the live dev stack beyond the existing 0003 tests: the throwaway with `INFRA_ENV=dev` runs the same files (A).
- Should the nested snippet stop passing its argument (a Caddy upgrade), the generated line becomes `import spa-header-values ""` for today's routes, the generated sites and `tests/0003-routes.sh`'s checks following, as a deviation (A).

## Files

| File | Change | For |
| --- | --- | --- |
| `caddy/Caddyfile` | modified: `(spa-header-values)`, the three shared values written once, one `header {args[0]}<field>` per field; `(spa-headers)` imports it with `""` (the generated `import spa-headers` lines unchanged); new `(spa-headers-app)` (the `vars app_headers yes` marker, then the values with `?`); the `(site)` snippet gets `handle_errors` (`import common-headers`; on the marker, the values with `?`), so every site, the shared host's included, has it once; comments | RQ-01, RQ-02, RQ-04, RQ-06, RQ-08 |
| `routes.sh` | modified: option `headers=` in `routes_generate`'s option loop (value `app` only; target `fr`, `en`, `ui` only, the spec's messages; twice: today's rule), kept per route in an array beside `bodies` and `prefixes`; `_routes_site` prints `import spa-headers-app` instead of `import spa-headers` for such a route; the unknown-option message and the usage comment name `headers=app` | RQ-01, RQ-02, RQ-04, RQ-05, RQ-07 |
| `README.md` | modified: "Routes file", the options block and the **Headers** bullet: `headers=app`, where it is accepted, what the browser receives, that the application then sends its policy on every response; the proxy's own error responses carry the common headers | RQ-07, RQ-08 |
| `tests/0015-proxy-facts.sh` | new: the facts above on a throwaway of the stack's proxy image (one block all or nothing, one directive per field, the nested snippet with `""` and `?`, `handle_errors` with `common-headers` and the marker; the rate limit's `429`, through `handle_errors`, keeps its `Retry-After` and gets `common-headers`), so that a Caddy upgrade that changes one fails here first | step 1 |
| `tests/0015-headers.sh` | new: throwaway proxies running `caddy/` (stack's image, `INFRA_ENV=dev`, then `demo` with `local_certs` as `tests/0003-demo-edge.sh`), a site generated by `routes.sh` from the fixture, echo upstreams sending their own headers, none, or `Report-Only`, stopped ones; the proxy's own errors on that site and on the shared host; then the registration refused in dev (`register-app.sh` with a fake `docker` on `PATH`, as `tests/0013-register.sh`'s `refused_before_docker`) | AC-01 to AC-06, AC-08 |
| `tests/fixtures/0015/` | new: `verif.routes` (`fr`, `en` with `headers=app`, `/fr/upload/*` with `max-body=1KB`, `/down/*` with `headers=app` to a stopped front end, `ui` without the option, `/ui-upload/*` `ui` with `max-body=1KB`, `/ui-down/*` `ui` stopped, a `gateway` stopped), `own-headers.caddy` (sends Content-Security-Policy, `X-Frame-Options: SAMEORIGIN`, `Referrer-Policy: unsafe-url`, no `Permissions-Policy`), `report-only.caddy`, `registry.txt` | AC-01 to AC-05, AC-08 |
| `tests/0003-routes.sh` | modified: generation with `headers=app` (the route's `import spa-headers-app`, the other routes' `import spa-headers`, the MCP site without either); refused: `headers=app` on `gateway`, `mcp`, `redirect`, `headers=self`, `headers=` twice | AC-05, AC-06 |
| `tests/fixtures/0003/verif-app-headers.routes`, `refused-headers-{gateway,mcp,redirect,value,twice}.routes` | new | AC-05, AC-06 |
| `tests/0003-demo-deploy.stand-in.sh` | modified: a routes file with `headers=app` on `gateway` through `sudo c4-app register`: exits 1, `<file>:<line>:`, no site installed | AC-06 |
| `docs/intent/0015-proxy-imposes-front-end-headers/plan.md` | new: this plan | — |
| `docs/intent/0015-proxy-imposes-front-end-headers/intent.md`, `docs/intent/README.md` | modified: status `planned`, index row, every row's status taken from its intent's own `intent.md` after `main` is merged (the branches' index carries stale rows: 0011 "proposed", a duplicate 0012) | — |

## Order of work

0. **Setup**: `git merge origin/main` once 0013 and 0011 are delivered, else `git merge origin/0013-stack-lacks-what-turu-and-hururaa-need` then `git merge origin/0011-demo-builds-and-script-errors`; the dev stack on 0013's images (`bash up.sh`). — skill: none — check: `git status --short` empty, `bash tests/run.sh` → `verification passed`.
1. **Facts**: `tests/0015-proxy-facts.sh`, on the stack's proxy image (`c4-infra/reverse-proxy`, with the rate-limit module): with `handle_errors` in a site, a `rate_limit` zone's `429` keeps its `Retry-After` header and carries `common-headers`. — skill: none — check: the test passes; a failing fact is a deviation before step 2 (the nested snippet failing: the engineer's third choice).
2. **The snippets and the errors' headers** in `caddy/Caddyfile` (`spa-header-values`, `spa-headers`, `spa-headers-app`, `handle_errors` in `site`), no generator change yet. — skill: none — check: `bash tests/0003-caddy-config.sh && bash tests/0003-routes.sh && bash tests/0003-demo-edge.sh`, then `bash up.sh && bash tests/0003-dev-routes.sh && bash tests/0013-rate-limit.sh` (the generated sites, today's headers on the application's responses, the `413`'s and the `429`'s statuses unchanged; the `429` of `tests/0013-rate-limit.sh` keeps its `Retry-After` and carries `X-Content-Type-Options: nosniff`, no `Server`).
3. **The option** in `routes.sh`, its cases in `tests/0003-routes.sh` and their fixtures. — skill: none — check: `bash tests/0003-routes.sh && bash tests/0003-caddy-config.sh`.
4. **The headers served**: `tests/0015-headers.sh` and `tests/fixtures/0015/`. — skill: none — check: `bash tests/0015-headers.sh`.
5. **The demo host's refusal**: `tests/0003-demo-deploy.stand-in.sh`. — skill: none — check: `bash tests/0003-demo-deploy.stand-in.sh`.
6. **Docs**: README "Routes file", `routes.sh`'s usage comment. — skill: none — check: `grep -n 'headers=app' README.md routes.sh` names it in both; reread against RQ-07 and RQ-08.
7. **Verification**: `bash tests/run.sh --all`; mutation checks: `routes.sh` and `caddy/Caddyfile` from step 0's head → `tests/0015-headers.sh`'s checks and `tests/0003-routes.sh`'s `headers=` checks `KO`; `caddy/Caddyfile` alone from step 0's head (v1's error headers) → `tests/0015-headers.sh`'s AC-08 checks `KO`; then `/sdlc-verify 0015`. — skill: sdlc-verify — check: `verification passed`.
8. **After the merge** (the human's): the deployment reloads the proxy with the new `caddy/`. — skill: sdlc-ship — check, on the demo host: `curl -sI https://faito.c4-soft.com/fr/` shows today's headers (one Content-Security-Policy, `X-Frame-Options: DENY`), Faito's routes file having no `headers=`, and `X-Content-Type-Options: nosniff` with no `Server`.

## Risks

- `handle_errors` in `site` reaches every site, the shared host's included → it only adds headers to responses the proxy makes itself (measured: statuses, `Content-Length: 0`, empty bodies, `respond 404` unchanged); Keycloak's, Grafana's and the applications' own error pages are their responses, not the proxy's, and keep today's headers; step 2 runs the 0003 and 0013 proxy tests before any generator change.
- The rate limit's `429` (0013, `caddy/Caddyfile:46` on 0013) goes through `handle_errors` too → it gains `common-headers`; step 1 shows on the stack's proxy image that it keeps its `Retry-After`, step 2 checks it on the dev stack (status, `Retry-After`, `nosniff`, no `Server`).
- `?` in a single block defaults all or nothing (measured) → one directive per field; AC-01's upstream sends two of the three, so a block would fail it.
- A Caddy upgrade changes how a snippet's `{args[0]}` passes through `spa-headers` → `tests/0015-proxy-facts.sh` fails first; the engineer's third choice applies.
- A route earlier in the file serves a path a `headers=app` route also matches → the marker is set by the route that serves, not matched by path: `handle_errors` follows first match.
- 0011 changes the same option loop (RQ-11) and `tests/0003-routes.sh`, and is delivered before this change → 0015 extends the `case` (`routes.sh:146` on 0013) and the unknown-option message (`:173`); it keeps the `unknown option '<opt>'` prefix and 0011's empty-key guard before `seen_options`, as 0011's AC-11 matches `unknown option '=x'`.
- 0013 or 0011 is not delivered when this starts → step 0 builds on their branches, as 0013's plan did on 0012's; a change of either after step 0 is merged again before step 7.
- An application relaxes its visitors' protection on the public demo host (PA-02, high risk) → the shared values stay the default of every response the application doesn't cover; README says it owns its policy from then on.

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| AC-01 | automated test | `tests/0015-headers.sh`: `/fr/x` through the dev and the demo configuration, each of the three headers once, the upstream's values (`Permissions-Policy`, which it doesn't send, the shared one) |
| AC-02 | automated test | `tests/0015-headers.sh`: the upstream sending none → the three shared values; `Report-Only` only → the shared Content-Security-Policy and the upstream's report-only one |
| AC-03 | automated test | `tests/0015-headers.sh`: a 2 KB `POST` on `/fr/upload/x` (`max-body=1KB`) → `413` with the three shared values; `/down/x` (front end stopped) → `502` with them |
| AC-04 | automated test | `tests/0015-headers.sh`: on `/fr/x`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin` (the upstream's `unsafe-url` replaced), no `Server`; `Strict-Transport-Security` in the demo configuration only |
| AC-05 | automated test | `tests/0015-headers.sh`: `ui` without the option → today's (two Content-Security-Policy, the shared one first) on its 200; `tests/0003-routes.sh`, `-caddy-config.sh`, `-demo-edge.sh`, `-dev-routes.sh` pass unchanged after step 2 |
| AC-06 | automated test | `tests/0003-routes.sh` (the five refused fixtures, `<file>:<line>:`, no site); `tests/0015-headers.sh` (dev registration: exit 1, `docker` never called); `tests/0003-demo-deploy.stand-in.sh` (`sudo c4-app register`: exit 1, no site installed) |
| AC-07 | command + review | `grep -n 'headers=app' README.md routes.sh`; README "Routes file" reread against RQ-07 |
| AC-08 | automated test + mutation check | `tests/0015-headers.sh`, dev and demo configurations: the stopped gateway's `502`, the stopped `ui` front end's `502`, the `ui` `413` (`max-body=1KB`), and a `502` of the shared host (its Keycloak stand-in stopped) each carry `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, no `Server`, HSTS in demo only; step 7: the same checks `KO` with step 0's `caddy/Caddyfile` |

## Deviations

<!-- filled during implementation: date — what — why — impact on files or proof -->

- 2026-10-28 — step 0. `main` merged (5b7cd70): 0013 and 0011 are delivered there (0011 on `main` locally, not pushed yet); the only conflict was the index's row. The branch is worked on under the local name `0015-impl` (tracking `origin/0015-proxy-imposes-front-end-headers`): the branch's own name is checked out in the worktree `../c4-infra-0015`, left alone. No new baseline run: the tree is `main`'s, verified by 0011's `--changed main --all` (43 tests).
- 2026-10-28 — step 4. `tests/fixtures/0015/` holds `registry.txt` (two applications: `verif`, whose front end answers, and `verif-down`, whose front end doesn't: on the demo host every front-end role goes to one upstream, `<app>.frontend:80`, so a stopped front end needs an application of its own), `verif.routes`, `verif-down.routes`, `refused-gateway.routes`, and one front-end stand-in answering by path (`frontend.caddy`: its own headers on `/fr/*`, none on `/en/*`, a report-only policy on `/report-only/*`, its own policy on `/ui/*`) in place of `own-headers.caddy` and `report-only.caddy`. Both throwaway proxies serve the sites generated for `demo` (service-name upstreams); `INFRA_ENV=dev` and `demo` differ by the environment's snippets only (the certificate, HSTS), which is what the test compares.
- 2026-10-28 — step 5. AC-06's registration through `sudo c4-app register` is in `tests/0002-accounts.stand-in.sh` (and its fixture `tests/fixtures/0002/routes-headers-app-gateway.routes`), not `tests/0003-demo-deploy.stand-in.sh`: the latter runs `register-app.sh` as root with no application account, the former already proves the other routes files' refusals through `sudo c4-app register` as Faito. Checks: refused, `routes-headers-app-gateway.routes:3: headers=app is for a front end (fr, en or ui), not for gateway`, Faito's site unchanged (`every check passed`).
- 2026-10-28 — step 7, review round (bootstrap: one; `code-review high`). `handle_errors` makes Caddy log the errors it handles at DEBUG only (measured on the stack's image: a `502` without it logs `"level":"error" … dial tcp: lookup nowhere … no such host`; with it, nothing): the `site` snippet gets an access log of the proxy's own errors only (`log` to stderr, `log_skip` for every request, `vars log_skip false` and `log_append error {err.message}` in `handle_errors`; measured: the `502`'s line at level error with its cause, a served request not logged); `tests/0015-headers.sh` checks both, and that a front end's `413` and `502` without `headers=app` keep the three shared values (today's); its containers named `c4-infra-test-0015-headers-*` (the facts test's prefix is `c4-infra-test-0015-facts`); `tests/0015-proxy-facts.sh` covers `caddy/` too; `tests/0002-accounts.stand-in.sh`'s unchanged-site check refuses an empty checksum; README says the proxy logs its own errors. Files: `caddy/Caddyfile` (in *Files*); no new file.

## Verification

### Verification — f9aaa62

- Verification command: `LC_ALL=C TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --changed main --all` at f9aaa62 → `total: 865.7 s for 35 test(s)` / `verification passed (--changed: 35 of 53 tests)` (2026-10-28); `--all` at the next milestone (CLAUDE.md)
- Risk tier: high (PA-02, the tech lead's decision: an application may relax its visitors' protection on its own origin)
- Reviews: bootstrap mode: 1 round; bugs (`code-review high`) 9 findings, 6 fixed / 3 answered; security (`security-review`) no finding (no text of the option reaches the site, the marker is per request and per site, `{err.message}` reaches the log only, Cookie and Authorization redacted in it); no `simplify` pass (bootstrap)
  - fixed (f9aaa62): `handle_errors` left the proxy's own errors' cause at DEBUG, absent from `docker compose logs reverse-proxy` (an access log of those errors only, measured: the cause at level error, a served request not logged); the front ends' `413` and `502` without `headers=app` now checked for today's three values; the headers test's containers named apart from the facts test's; the facts test covers `caddy/`; the stand-in's unchanged-site check refuses an empty checksum; the README names the log
  - answered: the other four refusals not run through `sudo c4-app register` — they are `routes.sh`'s, before any change, and one case end to end (gateway) proves the message passes through `c4-app` and `register-app.sh` unchanged; the five run in `tests/0003-routes.sh`
  - answered: `headers=self` on a gateway names the target first — the spec's messages; the target is the first thing to fix (`routes.sh:181`)
  - answered: the if/else and the two messages could be one parameter expansion each — kept explicit for the reader (`routes.sh:296`); `host_path` defined per test — the project's existing pattern (about twenty copies), a shared helper is its own change
- Mutation check: in throw-away worktrees at f9aaa62, `routes.sh` and `caddy/Caddyfile` of 5b7cd70 → `tests/0003-routes.sh` `10 check(s) failed`, `tests/0015-headers.sh` exits 1 (`unknown option 'headers=app'`); the Caddyfile without its `handle_errors` block → `tests/0015-headers.sh` `19 check(s) failed` (every error response's headers and the log, dev and demo; plus AC-06's message, which a fresh worktree fails for want of `.env`: reproduced unmutated, `INFRA_ENV … must be dev or demo`)
- Verifier: 8/8 criteria OK — table below; neighbouring flows on the live dev proxy (not restarted; its Caddyfile is HEAD's): the shared host's discovery and 404 carry nosniff, Referrer-Policy, no Server; Faito's `502`s carry them, `/fr/` the three shared values; the rate limit's `429` keeps `retry-after`; `docker logs` lists only the proxy's own errors, each with its cause, a dummy Cookie and Authorization as `REDACTED`; a front end sending all three headers through HEAD's `caddy/` (verifier's own run): each once with its value on `headers=app` routes
- Not verifiable here: plan step 8, the demo host after the push (`curl -sI https://faito.c4-soft.com/fr/`: one Content-Security-Policy, `X-Frame-Options: DENY`, nosniff, no Server)
- Files outside the plan: none (`tests/0002-accounts.stand-in.sh` and the fixtures' shape: *Deviations*)
- Details left (not KO): no automated check that a front end's own Permissions-Policy passes unchanged (the fixture sends none, per the plan; the verifier saw it pass); the dev registration check needs the repository's `.env` (as `tests/0013-register.sh`); the `429`'s headers on `caddy/` itself are checked by the facts test's copy and the live observation only

| Criterion | Result | Evidence |
| --- | --- | --- |
| AC-01 | OK | `tests/0015-headers.sh`, dev and demo: `ok - …, AC-01: its Content-Security-Policy, once`, `… its X-Frame-Options, once`, `… the shared Permissions-Policy it doesn't send, once` |
| AC-02 | OK | `ok - …, AC-02: a front end sending none: the three shared values`; the report-only policy kept beside the enforced shared one |
| AC-03 | OK | `413` and `502` with the three shared values, dev and demo; KO without `handle_errors` |
| AC-04 | OK | nosniff, `Referrer-Policy` (the front end's `unsafe-url` replaced), no Server, HSTS on demo only |
| AC-05 | OK | `/ui/x`: two policies, the shared first, `DENY SAMEORIGIN`; its `413`/`502` keep the three values; the 0003 tests pass, only additions to `0003-routes.sh` |
| AC-06 | OK | `0003-routes.sh`: the five refusals, `<file>:3:`, no site; `0015-headers.sh`: dev registration exit 1, line named, no docker call; `0002-accounts.stand-in.sh`: `sudo c4-app register` refused, Faito's site unchanged |
| AC-07 | OK | `grep -n 'headers=app' README.md routes.sh`: the options block, the bullet, the usage comment |
| AC-08 | OK | the gateway's, the stopped ui's and the shared host's `502`, the ui `413`: nosniff, Referrer-Policy, no Server, HSTS on demo only; KO without `handle_errors` |

