# Spec: No realm of the shared Keycloak protects its accounts against password guessing

- Intent: [0010](intent.md)
- Status: approved
- Version: 1
- Risk: high (rule: authentication — the lockout of every account of every realm; tech lead's agreement required)
- Policies applied: none yet; standing constraints: README design, `CLAUDE.md` (no password on a command line), 0006 (the registration account's rights)
- Approved: 2026-10-23, Jérôme Wacongne (PO, and tech lead for the high risk)

## Summary

Keycloak's brute-force detection is turned on, in temporary lockout mode with a linear wait, in the master realm when Keycloak creates it (its pre-configuration, 0009) and in each application's realm when its registration imports it. The settings are c4-infra's, the same in every realm, in dev and on the demo host; nothing locks an account for good.

## Requirements

- REQ-1 The brute-force settings c4-infra writes into a realm are: detection on (`bruteForceProtected`); temporary lockout only (`permanentLockout` off, `maxTemporaryLockouts` 0); first lockout after 10 failures (`failureFactor`); linear wait (`bruteForceStrategy` `LINEAR`), 1 minute more per further failure (`waitIncrementSeconds` 60), at most 15 minutes (`maxFailureWaitSeconds` 900); failures forgotten 12 hours after the last one (`maxDeltaTimeSeconds` 43200); Keycloak's defaults for quick logins (`quickLoginCheckMilliSeconds` 1000, `minimumQuickLoginWaitSeconds` 60). (intent: outcome and criterion)
- REQ-2 A registration that imports an application's realm (absent, or deleted first by `--reset-realms`) writes REQ-1's settings into it, whatever its export says. (intent: outcome, applications' realms)
- REQ-3 A registration that finds the realm already in Keycloak leaves it as it is: such a realm (Faito's in dev, registered before this change) gets REQ-1's settings when it is re-created (`--reset-realms`) (PA-1 decided). (intent: outcome, every realm)
- REQ-4 The master realm has REQ-1's settings from its creation: they are part of its pre-configuration (0009, REQ-1 and REQ-2), applied by Keycloak when it creates the realm, never to a master realm that exists; no administrator logs in for them. The existing stacks get them with 0009's documented re-creation of Keycloak's database. (intent: outcome, master realm; constraint 0006; 0009's PA-1 decision)
- REQ-5 (removed in the draft: no administrator's login, REQ-4)
- REQ-6 No setting c4-infra writes locks an account permanently. (intent: constraint)
- REQ-7 The registration account gets no right to change the master realm. (intent: constraint, 0006 REQ-2)
- REQ-8 The README states the settings, and that an application's realm export can't change them. (intent: outcome, the settings are c4-infra's)

## Out of scope

- Service accounts and client credentials: Keycloak's detection counts users' failed logins.
- Second factors (`maxSecondaryAuthFailures`, left at Keycloak's default).
- Any setting per application, and any watch of the settings once written (decided in the interview).

## Design

### Current behaviour

- Keycloak creates a realm with its detection off (`RealmManager`: `bruteForceProtected` false, `failureFactor` 30, strategy `MULTIPLE`). Dev at `08dfa3d`: realms `master` and `faito` answer `bruteForceProtected: false`.
- `register-app.sh` imports a realm only when it is absent, or after deleting it with `--reset-realms`; a realm already there is "left as it is" (`register-app.sh:259-273`). The registration account manages the registry's realms, their settings included (dev: `kc_registration get realms/faito --fields bruteForceProtected` answers).
- The registration account may not change the master realm (0006, AC-2). 0009 pre-configures the master realm when Keycloak creates it (an import Keycloak 26 applies to a master realm that doesn't exist yet, and skips once it does).

### Behaviour per persona

- Demo visitor, and any user: after 10 wrong passwords, the account is refused for 1 minute, even with the right password, Keycloak's usual "Invalid username or password" shown; each further failure adds 1 minute, up to 15; then the right password logs in.
- Demo operator and developer: the same for the master realm's administrators; an administrator can unlock an account in the console (the user's *temporarily locked* switch). An administrator locked out waits at most 15 minutes.
- Application: whatever its realm export says about brute force, its realm gets c4-infra's settings when its registration imports it.
- The stack's own logins as an administrator happen only when the registration account must be repaired (0006): each one that fails, with a stale bootstrap password, counts as one failure for that user.

### API and contracts

- The realm settings of REQ-1 (Keycloak's admin API, `realms/<realm>`).
- `register-app.sh`: same options; one more line per imported realm (settings written).
- The master realm's pre-configuration (0009) holds REQ-1's settings.

### User interface

None (Keycloak's console shows the settings in *Realm settings* → *Security defenses* → *Brute force detection*).

### Data

The realms' brute-force settings, in Keycloak's database.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| No password on a command line (`CLAUDE.md`) | no password involved: the master realm's settings come with its creation, the applications' realms' with the registration's existing login |
| 0006 REQ-2: the registration account, nothing else in the master realm | REQ-7: the master realm's settings come with its creation (REQ-4) |
| README design | REQ-8 |

## Points of attention

### PA-1 Realms already in Keycloak when their application registers

- Issue: Faito's realm in dev (registered before this change), and any realm a registration finds there, isn't imported again, so REQ-2 never reaches it.
- Options: A a registration that finds the realm with its detection off writes REQ-1's settings into it; detection on, left as it is (a realm turned off in the console gets it back at its application's next registration) / B only the realms imported from now on; the others keep theirs until a `--reset-realms` / C every registration writes them, imported or not (a realm's settings tuned in the console are replaced at each deployment of its application)
- Recommendation: A: every realm gets the protection at its application's next registration, and settings tuned with the detection on are kept, as decided in the interview.
- Decides: product owner
- Decision: B, at the realm's re-creation, as for the master realm (0009, PA-1); departs knowingly from the intent's "every realm": a realm registered before this change stays as it is until re-created (Jérôme Wacongne, product owner, 2026-10-23)

### PA-2 Visitors can lock the demo's shared accounts

- Issue: on the demo host, the applications' demo accounts have public passwords (Tickee's `secret`): anyone can lock one, for up to 15 minutes, with 10 wrong passwords, and do it again.
- Options: A accepted: the lockout is per account and temporary, an administrator can unlock it / B a higher threshold for the applications' realms on the demo host (no longer the same settings everywhere)
- Recommendation: A: the risk is a demo account unavailable for a while; B gives every other account of the demo the weaker protection.
- Decides: product owner
- Decision: A, accepted (Jérôme Wacongne, product owner, 2026-10-23)

## Acceptance criteria

- AC-1 Given a dev stack without its volumes, when `bash up.sh` runs, then the master realm has REQ-1's settings; given the stand-in demo host on an empty database, the same after the deployment. (REQ-1, REQ-4)
- AC-2 Given a realm export whose detection is off, or with other settings, when a registration imports it (absent, or with `--reset-realms`), then the realm has REQ-1's settings. (REQ-1, REQ-2)
- AC-3 Given a user of a registered realm, when 10 logins with a wrong password fail, then Keycloak reports the user temporarily disabled and refuses the right password; after the wait it logs in; an 11th failure makes the wait 2 minutes. (REQ-1)
- AC-4 Given a master realm that exists, with other brute-force settings, when the stack starts, then they are unchanged and no administrator logs in for them. (REQ-4)
- AC-5 Given Faito's realm registered before this change, when Faito registers again, then its brute-force settings are unchanged; when it registers with `--reset-realms`, then the realm has REQ-1's settings. (REQ-3)
- AC-7 Given an account with 30 failures, when 15 minutes have passed since the last one, then its right password logs in. (REQ-6)
- AC-8 Given the registration account, when it tries to change the master realm's brute-force settings, then Keycloak refuses. (REQ-7)

## Intent questions

- On the demo host, a visitor can lock a shared demo account for up to 15 minutes: accepted? → PA-2: accepted.
- The realms registered before this change: do they get the protection? → PA-1: at their re-creation.
- *Suggested solution*: the registration sets it on each realm it registers, the stack on the master realm when it starts → REQ-2; the master realm's in its pre-configuration instead (REQ-4, after 0009's PA-1 decision).

## Change log

- v1 — 2026-10-23 — first version
- v1 — 2026-10-23 — draft: the master realm's settings in its pre-configuration (0009's PA-1 decision): REQ-4 rewritten, REQ-5 and the former PA-3 (no administrator) removed
- v1 — 2026-10-23 — approved: PA-1 B (REQ-3 and AC-5 rewritten), PA-2 A; tech lead's agreement for the high risk (Jérôme Wacongne, PO and tech lead)
