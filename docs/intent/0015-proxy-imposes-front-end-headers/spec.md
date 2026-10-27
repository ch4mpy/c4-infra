# Spec: The shared proxy imposes its security headers on every application's front end

- Intent: [0015](intent.md)
- Status: approved
- Version: 1
- Risk: high (PA-02, decided by the tech lead: an application may relax its visitors' protection on its own origin, the public demo included; no risk rule names it; tech lead's agreement required)
- Policies applied: none yet; standing constraints: README design (one origin per application; one reverse proxy, the sites' headers written once), 0003 (one routes file, dev and demo alike), README "Routes file" (refusals before anything is registered), 0013 (the MCP origin, `_routes_site`)
- Approved: 2026-10-27, Jérôme Wacongne (product owner, and tech lead for the high risk)

## Summary

A front-end route (`fr`, `en`, `ui`) of an application's routes file may take `headers=app`: its Content-Security-Policy, `X-Frame-Options` and `Permissions-Policy` are then the application's, reaching the browser once each and unchanged, the shared values serving only as defaults for a response that lacks one, the proxy's own error responses included. The headers every site gets stay. Routes without the option keep today's headers. Same in dev and on the demo host; the option is refused anywhere else. This change lands after 0013, on its `routes.sh`.

## Requirements

- **RQ-01:** A route whose target is `fr`, `en` or `ui` may take the option `headers=app`. On that route, each of Content-Security-Policy, `X-Frame-Options` and `Permissions-Policy` that the application's response carries reaches the browser with the application's values only, unchanged: the shared value isn't added. (intent: outcome, criterion)
- **RQ-02:** On that route, each of the three headers a response lacks gets the shared value (`spa-headers`), header by header: on the application's responses and on the proxy's own (`413` of `max-body=`, `502`/`504` when the front end doesn't answer). A response with only `Content-Security-Policy-Report-Only` therefore gets the shared policy enforced as well. (intent: outcome, decided at acceptance: B)
- **RQ-03:** The headers every site gets stay on such a route: `X-Content-Type-Options`, `Referrer-Policy` (PA-01), no `Server`, HSTS on the demo host only. (intent: outcome)
- **RQ-04:** A route without the option gets exactly today's headers. (intent: outcome)
- **RQ-05:** Refused as `<file>:<line>: …`, the registration then registering nothing, in dev and through `sudo c4-app register` on the demo host: `headers=app` on `gateway`, `mcp` or `redirect`; `headers=` with any other value; `headers=` twice. (intent: criterion, constraint)
- **RQ-06:** Dev and the demo host serve the same headers from the same routes file; the defaults are the values of `spa-headers`, written once. (intent: constraint, 0003)
- **RQ-07:** README "Routes file" documents the option: where it is accepted, what the browser receives, that the application then owns its pages' policy and should send it on every response (static assets and error pages included). (intent: affected systems)

## Out of scope

- An application's own `Referrer-Policy` or any other header of `common-headers` (unless PA-01 decides otherwise).
- Any change to the shared values, to the gateway's, the MCP origin's or the shared host's headers.
- Checking the content of an application's policy: its own tests do (immo's CA-16).
- A floor the stack would keep under an application's policy: the intent gives the application the three headers whole.

## Design

### Current behaviour

- `routes.sh:145-175` parses the options (`to=`, `max-body=`, `prefix=`; unknown-option message at `:172`); `:258-260` prints `import spa-headers` for `fr`, `en`, `ui`. On 0013's branch the same line is in `_routes_site` (`routes.sh:280`), which also writes the MCP origin's site, never with `spa-headers`. `register-app.sh:296-315` generates the site before anything changes.
- Measured on 2026-10-27, a throwaway Caddy 2.11.4 with the stack's snippet shapes in front of stand-ins:
  - today, a front end sending its own headers: two Content-Security-Policy, two `X-Frame-Options` (`DENY`, `SAMEORIGIN`), two `Permissions-Policy`; its `Referrer-Policy: unsafe-url` comes out `strict-origin-when-cross-origin`;
  - today, the proxy's own `413` and `502` on a front-end route carry the three shared headers;
  - with Caddy's `?<field>` defaults instead: the front end's values alone, unchanged; a missing one gets the default; a `Report-Only` alone gets the shared policy beside it; **but the proxy's own `413` and `502` get none of the three**. `?<field>` alone doesn't meet RQ-02: the plan covers those responses.

### Behaviour per persona

- **Application**: opts in route by route; then owns its pages' policy, and sends it on every response, or gets the shared one.
- **Developer**: sees in dev what the demo host serves (0003).
- **Demo visitor**: on such a route, the page's protection is the application's.
- **Demo operator**: nothing new; `sudo c4-app register` refuses as dev does.

### API and contracts

Routes file, one more option:

```text
headers=app   fr, en or ui only: the front end's Content-Security-Policy, X-Frame-Options and
              Permissions-Policy are the application's (the shared values for a response without them)
```

Messages: `headers=app is for a front end (fr, en or ui), not for <gateway|mcp|a redirect>`; `headers= takes app, not '<value>'`; `headers= given twice` (today's rule); the unknown-option message names `headers=` too. Alternatives set aside: new targets (`fr-app`…: three more roles to route); one flag per application (the intent wants it route by route).

### User interface

None.

### Data

None.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| README design: one origin per application | the option changes the application's own site only |
| README design: the sites' headers written once | the defaults are `spa-headers` (RQ-06) |
| 0003: dev and demo alike | RQ-06, AC-01 in both |
| README "Routes file": refused before anything is registered | RQ-05 |
| 0013: the MCP origin gets the sites' headers, not the front ends' | RQ-05: `mcp` refuses the option |

## Points of attention

### PA-01: `Referrer-Policy` on such a route

- Issue: `common-headers` replaces an application's own `Referrer-Policy` on every site (measured). The intent keeps the common headers; nothing asks for this one yet.
- Options: A the stack's value stays / B on a `headers=app` route, the stack's value as a default only / C a default only, on every route
- Recommendation: A: no application needs it today; a later intent if one does.
- Decides: PO
- Decision: A, the stack's value stays (PO, Jérôme Wacongne, 2026-10-27)

### PA-02: Risk level

- Issue: no risk rule names a page's security headers. The option lets an application relax, on its own origin and on the public demo host, what protects its visitors today (scripts' sources, framing): RQ-02 keeps a default, not a floor.
- Options: A high (tech lead's review) / B standard
- Recommendation: A: it changes a protection of the visitors' sessions that the stack guarantees today; adding the rule to the README's risk rules is the PO's call, apart.
- Decides: tech lead
- Decision: A, high (tech lead, Jérôme Wacongne, 2026-10-27)

## Acceptance criteria

- **AC-01:** Given a route `/fr/* fr headers=app` and a front end sending its own Content-Security-Policy, `X-Frame-Options: SAMEORIGIN` and `Permissions-Policy`, when `/fr/x` is requested in dev and on the stand-in demo host, then each header appears once, with the front end's value. (RQ-01, RQ-06)
- **AC-02:** Given that route and a front end sending none of the three, then each has the shared value; sending only `Content-Security-Policy-Report-Only`, then the shared Content-Security-Policy and the front end's report-only one. (RQ-02)
- **AC-03:** Given that route with `max-body=1KB`, when a 2 KB body is posted, then the `413` carries the three shared values; with the front end stopped, the `502` does too. (RQ-02)
- **AC-04:** Given that route, then `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, no `Server`, and HSTS on the demo host only. (RQ-03)
- **AC-05:** Given a front-end route without the option, then its headers are today's, and the 0003 tests pass unchanged. (RQ-04)
- **AC-06:** Given `headers=app` on `gateway`, `mcp` or `redirect`, `headers=self`, or `headers=app` twice, when the application registers in dev and through `sudo c4-app register` on the stand-in, then it exits 1 with `<file>:<line>: …` and registers nothing. (RQ-05)
- **AC-07:** Given the README and `routes.sh`'s usage text, then both name the option, where it is accepted and what it changes. (RQ-07)

## Intent questions

- Notation and hook? → `headers=app` on `fr`, `en`, `ui` (API and contracts); the code it touches is in Current behaviour, the hook is the plan's.
- What does a response without these headers get? → B, decided at acceptance (PO, 2026-10-27); `?<field>` covers the application's responses, not the proxy's own `413`/`502` (measured) → RQ-02.
- Does `Referrer-Policy` stay the stack's? → PA-01.
- High risk? → PA-02.

## Change log

- v1 — 2026-10-27 — first version
- v1 — 2026-10-27 — approved: PA-01 A, PA-02 A (high risk)
