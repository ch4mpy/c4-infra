# Spec: No realm of the shared Keycloak protects its accounts against password guessing

- Intent: [0010](intent.md)
- Status: approved
- Version: 2
- Risk: high (rule: authentication — the lockout of every account of the applications' realms; tech lead's agreement required)
- Policies applied: none yet; standing constraints: README design, `CLAUDE.md` (no password on a command line), 0006 (the registration account's rights)
- Approved: v1 2026-10-23; v2 2026-10-23, Jérôme Wacongne (PO, and tech lead for the high risk)

## Summary

Keycloak's brute-force detection is turned on, in temporary lockout mode with a linear wait, in each application's realm when its registration imports it. The settings are c4-infra's, the same in every application's realm, in dev and on the demo host; nothing locks an account for good. The master realm keeps Keycloak's default, no detection (PA-03): its administrators can't be locked out of the console the demo host publishes.

## Requirements

- **RQ-01:** The brute-force settings c4-infra writes into a realm are: detection on (`bruteForceProtected`); temporary lockout only (`permanentLockout` off, `maxTemporaryLockouts` 0); first lockout after 10 failures (`failureFactor`); linear wait (`bruteForceStrategy` `LINEAR`), 1 minute more per further failure (`waitIncrementSeconds` 60), at most 15 minutes (`maxFailureWaitSeconds` 900); failures forgotten 12 hours after the last one (`maxDeltaTimeSeconds` 43200); Keycloak's defaults for quick logins (`quickLoginCheckMilliSeconds` 1000, `minimumQuickLoginWaitSeconds` 60). (intent: outcome and criterion)
- **RQ-02:** A registration that imports an application's realm (absent, or deleted first by `--reset-realms`) writes RQ-01's settings into it, whatever its export says. (intent: outcome, applications' realms)
- **RQ-03:** A registration that finds the realm already in Keycloak leaves it as it is: such a realm (Faito's in dev, registered before this change) gets RQ-01's settings when it is re-created (`--reset-realms`) (PA-01 decided). (intent: outcome, every realm)
- **RQ-04:** The master realm has no brute-force detection (Keycloak's default; its pre-configuration, 0009, sets none): nobody can lock its administrators out of the console (PA-03 decided). Its administrators' passwords are long and random (`openssl rand`, `docs/demo-setup.md`), out of the reach of guessing. (v2; departs knowingly from the intent's "the master realm and every application's")
- **RQ-05:** (removed in the draft: no administrator's login, RQ-04)
- **RQ-06:** No setting c4-infra writes locks an account permanently. (intent: constraint)
- **RQ-07:** The registration account gets no right to change the master realm. (intent: constraint, 0006 RQ-02)
- **RQ-08:** The README states the settings, that an application's realm export can't change them, Keycloak's quick-login rule (two failures less than a second apart lock for a minute), and that the master realm has none. (intent: outcome, the settings are c4-infra's)

## Out of scope

- Service accounts and client credentials: Keycloak's detection counts users' failed logins.
- Second factors (`maxSecondaryAuthFailures`, left at Keycloak's default).
- Any setting per application, and any watch of the settings once written (decided in the interview).

## Design

### Current behaviour

- Keycloak creates a realm with its detection off (`RealmManager`: `bruteForceProtected` false, `failureFactor` 30, strategy `MULTIPLE`). Dev at `08dfa3d`: realms `master` and `faito` answer `bruteForceProtected: false`.
- `register-app.sh` imports a realm only when it is absent, or after deleting it with `--reset-realms`; a realm already there is "left as it is" (`register-app.sh:259-273`). The registration account manages the registry's realms, their settings included (dev: `kc_registration get realms/faito --fields bruteForceProtected` answers).
- The registration account may not change the master realm (0006, AC-02). 0009 pre-configures the master realm when Keycloak creates it (an import Keycloak 26 applies to a master realm that doesn't exist yet, and skips once it does).

### Behaviour per persona

- Demo visitor, and any user: after 10 wrong passwords, the account is refused for 1 minute, even with the right password, Keycloak's usual "Invalid username or password" shown; each further failure adds 1 minute, up to 15; then the right password logs in.
- Demo operator and developer: an administrator can unlock an application's account in the console (on the user's page). The master realm's administrators are never locked (RQ-04).
- Application: whatever its realm export says about brute force, its realm gets c4-infra's settings when its registration imports it.

### API and contracts

- The realm settings of RQ-01 (Keycloak's admin API, `realms/<realm>`).
- `register-app.sh`: same options; one more line per imported realm (settings written).

### User interface

None (Keycloak's console shows the settings in *Realm settings* → *Security defenses* → *Brute force detection*).

### Data

The realms' brute-force settings, in Keycloak's database.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| No password on a command line (`CLAUDE.md`) | no password involved: the applications' realms' settings go with the registration's existing login |
| 0006 RQ-02: the registration account, nothing else in the master realm | RQ-07: nothing is written into the master realm (RQ-04) |
| README design | RQ-08 |

## Points of attention

### PA-01: Realms already in Keycloak when their application registers

- Issue: Faito's realm in dev (registered before this change), and any realm a registration finds there, isn't imported again, so RQ-02 never reaches it.
- Options: A a registration that finds the realm with its detection off writes RQ-01's settings into it; detection on, left as it is (a realm turned off in the console gets it back at its application's next registration) / B only the realms imported from now on; the others keep theirs until a `--reset-realms` / C every registration writes them, imported or not (a realm's settings tuned in the console are replaced at each deployment of its application)
- Recommendation: A: every realm gets the protection at its application's next registration, and settings tuned with the detection on are kept, as decided in the interview.
- Decides: product owner
- Decision: B, at the realm's re-creation, as for the master realm (0009, PA-01); departs knowingly from the intent's "every realm": a realm registered before this change stays as it is until re-created (Jérôme Wacongne, product owner, 2026-10-23)

### PA-02: Visitors can lock the demo's shared accounts

- Issue: on the demo host, the applications' demo accounts have public passwords (Tickee's `secret`): anyone can lock one, for up to 15 minutes, with 10 wrong passwords, and do it again.
- Options: A accepted: the lockout is per account and temporary, an administrator can unlock it / B a higher threshold for the applications' realms on the demo host (no longer the same settings everywhere)
- Recommendation: A: the risk is a demo account unavailable for a while; B gives every other account of the demo the weaker protection.
- Decides: product owner
- Decision: A, accepted (Jérôme Wacongne, product owner, 2026-10-23)

### PA-03: Anyone can keep the master realm's administrators locked out of the console (v2)

- Issue (raised by the security review of the implementation): on the demo host, `/auth/admin/` and the master realm's password grant are public; the administrator's name is guessable (`admin`, `admin@<INFRA_HOST>`); two failures less than a second apart lock for a minute, and one failed login every few minutes keeps the account locked. The console and the registration account's repair (0006) are then out of reach, and another administrator is just as lockable. The password itself, random, is out of the reach of guessing.
- Options: A keep the lockout on the master realm, with a non-default administrator name, no login by e-mail, a host-side recovery, and the console's restriction as a new intent / B no lockout on the master realm, the applications' realms keep it / C restrict the console and the master realm from the internet in this change (what the demo host exposes: a new spec cycle)
- Recommendation: A.
- Decides: product owner, with the tech lead's agreement (high risk)
- Decision: B, no lockout on the master realm (Jérôme Wacongne, product owner and tech lead, 2026-10-23); departs knowingly from the intent's "the master realm and every application's"

## Acceptance criteria

- **AC-01:** Given the stack started (dev), then the master realm has no brute-force detection, whatever its creation (before or after 0009). (RQ-04)
- **AC-02:** Given a realm export whose detection is off, or with other settings, when a registration imports it (absent, or with `--reset-realms`), then the realm has RQ-01's settings. (RQ-01, RQ-02)
- **AC-03:** Given a user of a registered realm, when 10 logins with a wrong password fail, then Keycloak reports the user temporarily disabled and refuses the right password; after the wait it logs in; an 11th failure makes the wait 2 minutes. (RQ-01)
- **AC-05:** Given Faito's realm registered before this change, when Faito registers again, then its brute-force settings are unchanged; when it registers with `--reset-realms`, then the realm has RQ-01's settings. (RQ-03)
- **AC-07:** Given an account with 30 failures, when 15 minutes have passed since the last one, then its right password logs in. (RQ-06)
- **AC-08:** Given the registration account, when it tries to change the master realm's brute-force settings, then Keycloak refuses. (RQ-07)

## Intent questions

- On the demo host, a visitor can lock a shared demo account for up to 15 minutes: accepted? → PA-02: accepted.
- The realms registered before this change: do they get the protection? → PA-01: at their re-creation.
- *Suggested solution*: the registration sets it on each realm it registers, the stack on the master realm when it starts → RQ-02; the master realm has none (RQ-04, PA-03).

## Change log

- v1 — 2026-10-23 — first version
- v1 — 2026-10-23 — draft: the master realm's settings in its pre-configuration (0009's PA-01 decision): RQ-04 rewritten, RQ-05 and the former PA-03 (no administrator) removed
- v1 — 2026-10-23 — approved: PA-01 B (RQ-03 and AC-05 rewritten), PA-02 A; tech lead's agreement for the high risk (Jérôme Wacongne, PO and tech lead)
- v2 — 2026-10-23 — PA-03 raised by the implementation's security review and decided B: no lockout on the master realm (RQ-04, the summary, AC-01 rewritten; AC-04 removed: nothing in the master realm to keep); RQ-08 also names the quick-login rule (the bug review). Approved by the decision itself (Jérôme Wacongne, PO and tech lead)
