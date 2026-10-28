# Spec: The shared Keycloak offers no simulated Google, Facebook or Apple provider to try a social login

- Intent: [0016](intent.md)
- Status: approved
- Version: 1
- Risk: high (rules: authentication, a login an application's realm trusts; the isolation between applications, three realms every application shares; what a host exposes, look-alike login pages on the demo host's public origin; tech lead's agreement required)
- Policies applied: none yet; standing constraints: README design (one origin for the shared services, every issuer `https://<infra host>/auth/realms/<realm>`), Faito's decision 0001, 0004 (the registry refuses what the stack owns), 0005 and 0012 (themes), 0006 (the registration account), 0007 (one network per application), 0009 and 0010 (the stack's realms are imported by `keycloak-import`; brute-force settings), 0013 (Keycloak 26.8.1, merged first)
- Approved: 2026-10-27, Jérôme Wacongne (product owner, and tech lead for the high risk)

## Summary

The shared Keycloak gets three realms of its own that play Google, Facebook and Apple, in dev and on the demo host: a login theme that recalls each one and says it is simulated, seeded accounts, no external service. An application's realm declares one as an OpenID Connect provider, with the one client every application shares in that simulated realm, whose id and secret the README publishes (PA-02): no registration step. The registry reserves their names; the README says how to declare them and what differs from the real providers.

## Requirements

- **RQ-01:** The stack owns three realms, one per provider (names: PA-01), created by the stack itself, as the master realm is: on a new stack, and on an existing one at its next start (`up.sh`, the demo's deployment), without changing any other realm; a simulated realm that exists is left as it is. (intent: outcome)
- **RQ-02:** Each serves OpenID Connect's discovery, authorization, token, user info and keys at its issuer `https://<infra host>/auth/realms/<name>`, in dev and on the demo host. (intent: outcome, an application's realm declares it as an OpenID Connect provider)
- **RQ-03:** Each has a login theme of the stack that recalls its provider's colours, layout and type, with no logo, trademark or brand presented as genuine, and that says on every page that it is a simulated provider of c4-infra and must never receive a real password (PA-04). (intent: constraint on themes)
- **RQ-04:** Each holds the seeded accounts of PA-05, with passwords the README publishes; no self-registration, no password reset by mail; no brute-force protection (public passwords: a lockout would only let anyone lock them, as the master realm's reasoning in 0010). (intent: outcome, seeded accounts; constraint, demo host)
- **RQ-05:** The tokens and user info of each realm carry the claims its provider gives an application, within the limits of PA-03. (intent: outcome, "as they would through Google, Facebook or Apple")
- **RQ-06:** Each simulated realm holds one confidential client, created with the realm by the stack, shared by every application realm that declares it; its id and secret are public (README); its redirect URIs accept a broker endpoint of a realm of the infra host, `https://<infra host>/auth/realms/*`, and no other origin. No registration creates, changes or deletes anything in a simulated realm (PA-02). (intent: open question, the client)
- **RQ-07:** The registry refuses an entry that claims a simulated realm's name or a stack theme's name, naming the line, as it refuses `master`. (intent: open question, the names; 0004)
- **RQ-08:** No simulated realm, nor any file of the stack, holds a URL or credential of Google, Facebook or Apple. (intent: constraint)
- **RQ-09:** The README lists the simulated realms, their issuers, accounts and passwords, how an application's realm declares one (alias, issuer, browser-facing and back-channel URLs), what differs from the real provider (PA-03), and that a change to a simulated realm's file reaches an existing stack only once that realm is deleted. (intent: outcome)

## Out of scope

- The real providers, Apple's through an extension included (0014, rejected on 2026-10-27 in favour of this intent).
- An application's own realm, its first-login flow and account linking: the application's (the skills' intent 0057 for generated projects).
- Any other simulated provider (Office 365 is a project's own realm: the skills' intent 0056).

## Design

### Current behaviour

- The stack owns one realm, `master`, imported by the one-shot `keycloak-import` from `keycloak-import/` with `--override false` at each start (`compose.yml:100-140`): a realm already in the database is left alone, one missing is imported. Application realms are imported by `register-app.sh` as the registration account (`register-app.sh:339-391`), which adds the brute-force settings of 0010.
- `keycloak/themes/` holds the applications' themes only, filled by their registrations and git-ignored (`.gitignore`), mounted whole into Keycloak (`compose.yml:157-158`); the stack has no theme.
- The registry reserves `master` and Keycloak's built-in themes (`registry.sh:46-56`, `:205-210`).
- Keycloak's OpenID Connect provider takes separate authorization (browser), token, user info and keys URLs, and client authentication by secret or by a JWT signed with the declaring realm's key (Keycloak 26.8.1, `server_admin/topics/identity-broker/oidc.adoc`). Its `google` and `facebook` providers have their endpoints built in, and Facebook's reads the Graph API: an application's realm declares a simulated provider as `oidc`, where it declares the real one as `google` or `facebook` (PA-03).
- Keycloak runs on every application's network as `keycloak` (0007): the back-channel URLs are `http://keycloak:8080/auth/realms/<name>/…` in both environments (0013, RQ-15).

### Behaviour per persona

- Developer: declares the simulated Google in their realm (alias `google`, say), registers, clicks "Google" on their login page, signs in as a seeded account on the simulated page, comes back logged in to the application.
- Demo visitor: the same on the demo host, with the published accounts; the page tells them it is simulated.
- Demo operator: nothing to do; the next deployment creates the realms.
- Application: its realm export declares the provider with the shared client's id and secret (RQ-06); its registration is unchanged.

### API and contracts

- Issuer: `https://<infra host>/auth/realms/<name>`; authorization URL on that issuer; token, user info and keys on `http://keycloak:8080/auth/realms/<name>/protocol/openid-connect/…`.
- Client in a simulated realm: one per simulated realm, its id and secret published by the README (RQ-06); any application realm of the infra host may use it.

### User interface

Three login themes, each with a banner on every page: "Simulated <provider> — c4-infra test provider. Never type your real <provider> password." No other page.

### Data

Keycloak only: three realms, their seeded users, one shared client each.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| README design: one origin for the shared services, one issuer form | RQ-02: the simulated realms are ordinary realms of that origin |
| 0004: the registry refuses what the stack owns | RQ-07 |
| 0005, 0012: a theme holds no `${`, no link | RQ-03: the stack's themes follow the same rules, checked by the same tests |
| 0006: the registration account manages the registry's realms only | Unchanged: no registration touches a simulated realm (RQ-06) |
| 0007: an application reaches none of the others | Unchanged on the network; in the simulated realms, no isolation between applications, accepted (PA-02 C): the client and the accounts are public, an application's realm trusts only what a simulated login asserts |
| 0009: the stack's realms are imported by `keycloak-import` | RQ-01 |
| 0010: brute-force protection of the applications' realms | RQ-04: none on the simulated realms, as on `master`, for public passwords |

## Points of attention

### PA-01: The simulated realms' names

- Issue: an issuer the application's users and logs show; names no application may take.
- Options: A) `simulated-google`, `simulated-facebook`, `simulated-apple` / B) `google`, `facebook`, `apple`.
- Recommendation: A: the issuer says what it is (`…/realms/simulated-google`), and the plain names stay free for a realm that brokers a real provider.
- Decides: PO
- Decision: A, `simulated-google`, `simulated-facebook`, `simulated-apple` (PO, Jérôme Wacongne, 2026-10-27)

### PA-02: How an application's client authenticates, and who creates it

- Issue: RQ-06 needs the registration to create a client in a stack realm, beyond the registry's realms; a shared secret would let any application use another's client.
- Options: A) the registration creates the client, authenticated by a JWT the declaring realm signs (its keys at `http://keycloak:8080/auth/realms/<realm>/protocol/openid-connect/certs`): no secret anywhere; the registration account may manage these three realms' clients / B) the same, with a secret the registration generates and writes into both the client and the declaring realm's provider / C) one shared confidential client per simulated realm, its secret public, any realm's broker endpoint allowed: no registration change, no isolation between applications.
- Recommendation: A: no secret to keep, and each client answers one realm; the plan measures it on 26.8.1 first, B as fallback.
- Decides: tech lead
- Decision: C, one shared client per simulated realm, its secret public, no registration change; no isolation between applications in the simulated realms, accepted knowingly; RQ-06, AC-04 and AC-05 rewritten accordingly (tech lead, Jérôme Wacongne, 2026-10-27; against the recommendation)

### PA-03: How close to the real providers

- Issue: the application's realm declares `oidc` where production declares `google` or `facebook`; Apple gives the name at the first authorization only, outside the token, and may give a private relay address; Facebook's `email` may be missing.
- Options: A) standard OpenID Connect claims per provider (Google: `email`, `email_verified`, `name`, `given_name`, `family_name`, `picture`; Facebook: `name`, `email` when the account has one; Apple: `email`, `email_verified`, `is_private_email`, no name), the differences listed in the README / B) A plus Apple's name posted once at the first authorization / C) every claim the same, no quirk.
- Recommendation: A: it tests what an application meets (no name from Apple, no address from some Facebook accounts, relay addresses) without code of the stack inside Keycloak; B needs an extension, which 0014's rejection rules out.
- Decides: PO
- Decision: A (PO, Jérôme Wacongne, 2026-10-27)

### PA-04: Look-alike login pages on the demo host's public origin

- Issue: `infra.c4-soft.com` serves every application's login; a page that looks like Google's or Apple's sign-in may be flagged as deceptive by browsers' safe-browsing lists, which would block that origin, every application's login with it.
- Options: A) themes recall colours and layout, with the banner of the user interface, in both environments / B) A in dev, a neutral theme naming the provider on the demo host / C) the simulated realms in dev only.
- Recommendation: B: the demo keeps the flows and loses only the look that risks the shared origin.
- Decides: PO
- Decision: A, the look-alike themes in both environments, the risk of a deceptive-site flag on the shared origin accepted knowingly (PO, Jérôme Wacongne, 2026-10-27, at draft)

### PA-05: Seeded accounts

- Issue: which accounts exercise what an application must handle.
- Options: A) per realm, two accounts with verified addresses on a reserved domain (`*.test`), plus: an Apple account with a private relay address, a Facebook account without an address / B) two accounts per realm, nothing else.
- Recommendation: A: the particular cases are the reason to simulate; a `.test` address is no one's, so a seeded account can't claim a real user's.
- Decides: PO
- Decision: A (PO, Jérôme Wacongne, 2026-10-27, at draft)

### PA-06: Public passwords for accounts an application may trust

- Issue: on the demo host anyone signs in as a seeded account; an application realm that links a brokered account to a local one by address (trust email) lets that visitor into the local account with the same address.
- Options: A) accepted: seeded addresses on `.test` (PA-05), and the README warns against automatic linking with them / B) the simulated realms in dev only (PA-04 C).
- Recommendation: A, knowingly: the demo's shared accounts are already public (0010, PA-02).
- Decides: PO
- Decision: A, accepted knowingly (PO, Jérôme Wacongne, 2026-10-27)

## Acceptance criteria

- **AC-01:** Given a new stack and one started before this change, when `up.sh` runs (and the demo's deployment on the stand-in host), then the three simulated realms exist, the other realms are unchanged, and a second start changes nothing. (RQ-01)
- **AC-02:** Given each simulated realm, when its discovery document is read, then its issuer is `https://<infra host>/auth/realms/<name>` in dev and on the stand-in host. (RQ-02)
- **AC-03:** Given a test application realm declaring the simulated Google, when it registers and a seeded account signs in through the browser flow, then the application realm holds a brokered user with the account's claims; likewise for Facebook and Apple, with PA-03's differences. (RQ-05, RQ-06, intent criterion)
- **AC-04:** Given two registered application realms declaring the same simulated provider with its shared client, when a seeded account signs in through each, then both come back logged in; an authorization request of the shared client with a redirect URI outside the infra host is refused. (RQ-06)
- **AC-05:** Given a simulated realm, when an application registers with a realm that declares it, then the simulated realm's clients, users and settings are the same before and after. (RQ-06)
- **AC-06:** Given a registry entry claiming a simulated realm's name or a stack theme's, then `registry.sh` refuses it, naming the line. (RQ-07)
- **AC-07:** Given each simulated realm, then registration and password reset are off, its users are PA-05's, and every login page shows the banner; the stack's themes pass 0012's checks. (RQ-03, RQ-04)
- **AC-08:** Given the repository, then no file holds `accounts.google.com`, `facebook.com` or `appleid.apple.com` outside documentation of what is simulated. (RQ-08)

## Intent questions

- Their names, and whether the registry reserves them → PA-01; reserved: RQ-07.
- How an application gets its client, and its return address → RQ-06: one shared client per simulated realm, public, any broker endpoint of the infra host (PA-02 C).
- Which accounts are seeded, and whether an application may add its own → PA-05; an application adds none (a shared realm: its accounts would be every application's) (PO, 2026-10-27).
- How far a realm declaring a simulated provider may differ from its realm with the real one → PA-03: the provider type (`oidc`) and its URLs differ, the alias and the broker endpoint stay.
- Constraint "Independent of intent 0014 … either can be delivered first": stale, 0014 was rejected on 2026-10-27, replaced by this intent; the real Apple is out of scope.

## Change log

- v1 — 2026-10-27 — first version; PA-04 and PA-05 decided by the PO at draft, an application adds no account (PO)
- v1 — 2026-10-27 — approved: PA-01 A, PA-02 C (against the recommendation: one shared public client, RQ-06, AC-04 and AC-05 rewritten), PA-03 A, PA-06 A
