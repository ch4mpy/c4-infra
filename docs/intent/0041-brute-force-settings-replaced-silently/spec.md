# Spec: register-app.sh replaces an application's brute-force settings with the stack's, without a word

- Intent: [0041](intent.md)
- Status: approved
- Version: 3
- Risk: high (authentication: the brute-force protection of the applications' realms, in dev and on the demo host)
- Policies applied: none yet; standing constraints: 0010 (the master realm without detection, the registration account unable to change it; a realm already in Keycloak kept as it is), CLAUDE.md
- Approved: 2026-10-30, Jérôme Wacongne (PO, also tech lead; in the session, PA-01 decided); v2 2026-10-30, the same (PA-02 decided); v3 2026-10-30, the same (PA-03 decided)

## Summary

`register-app.sh` stops imposing the stack's brute-force settings on a realm it creates: each setting the export holds is kept as the export says, the detection's switch included; the stack's value fills each one it doesn't hold; the registration names the settings it filled, and says when the realm has no detection. On the demo host, an export that would lock an account for good, or for more than 15 minutes at a time, is refused (v2, v3). Changes 0010's RQ-01 as to the applications' realms ("whatever its export says"); the rest of 0010 holds.

## Requirements

- **RQ-01:** A realm `register-app.sh` creates keeps each of the ten brute-force settings its export holds (`bruteForceProtected`, `permanentLockout`, `maxTemporaryLockouts`, `failureFactor`, `bruteForceStrategy`, `waitIncrementSeconds`, `maxFailureWaitSeconds`, `maxDeltaTimeSeconds`, `quickLoginCheckMilliSeconds`, `minimumQuickLoginWaitSeconds`), as the export says; a setting the export gives as `null` counts as not held. The export holds a setting at its top level or in its `attributes`, which Keycloak writes after the top level when it creates a realm (26.8.1, `DefaultExportImportManager.importRealm`): an attribute wins (v2). (intent: proposed outcome; PA-01)
- **RQ-02:** Each setting the export doesn't hold takes the stack's value (0010's: detection on, no permanent lockout, no limit of temporary lockouts, 10 failures, linear, 60 s more per failure, at most 900 s, failures forgotten after 43200 s, quick logins under 1000 ms locking 60 s). (intent: proposed outcome)
- **RQ-03:** For each realm it creates, the registration prints one line naming the settings it took from the stack, or saying that the export holds them all; and one more when the realm has no detection (`bruteForceProtected: false` in its export). (intent: problem, "without a word")
- **RQ-04:** A realm already in Keycloak is left as it is, as today; `--reset-realms` creates it again under RQ-01 to RQ-03. (0010, constraint)
- **RQ-05:** README ("Brute-force protection") and `docs/migration.md` state the rule, its consequence for an export with the detection off, how an application sets its own, and the demo host's refusal of RQ-06. (intent: proposed outcome)
- **RQ-06:** On the demo host (`INFRA_ENV=demo`), `register-app.sh` refuses a realm export whose `permanentLockout`, at its top level or in its `attributes` (RQ-01), is anything but absent, `null` or `false` (Keycloak reads it as Jackson does: `"TRUE"` and `1` are true; the string `"false"` is accepted, as by the CIMD check of intent 0013), before anything changes, naming the file and the value, whether the realm is already in Keycloak or not; in dev, RQ-01 holds unchanged. (PA-02)
- **RQ-07:** On the demo host, `register-app.sh` refuses as well, in the same places, at the same moment and in the same form as RQ-06, an export whose `maxFailureWaitSeconds` is anything but absent, `null`, or a number at most 900 (or a string of its digits, as Java's `Integer.valueOf` reads it: not `"nan"`), and one whose `maxSecondaryAuthFailures` is anything but absent, `null` or 0 (or `"0"`): Keycloak caps every temporary lockout at the first, and disables an account for good after that many wrong second-factor codes when the second is above 0 (26.8.1, `DefaultBruteForceProtector.failure`); in dev, RQ-01 holds unchanged. (PA-03)

## Out of scope

- The master realm (0010: no detection, unchanged).
- Faito's export: its repository's.
- Realms already in Keycloak, in dev or on the demo host (RQ-04).

## Design

### Current behaviour

`register-app.sh:402-405` builds `brute_force`, ten `-s key=value` options, and `:447` creates each realm with them after its file (`account -i create realms -f - … "${brute_force[@]}" < "$file"`): `-s` wins over the file. `:448` prints "brute-force protection set". The real exports hold all ten settings: Faito's `bruteForceProtected: false` and 30 failures (Keycloak's defaults), Tickee's four realms and immo's `true` and 5 failures (read 2026-10-30). `tests/fixtures/0010/verif-lockout-realm.json` holds `bruteForceProtected: false`, `failureFactor: 30`, `bruteForceStrategy: MULTIPLE`.

### Target behaviour

- The stack's ten values stay in one list, as `key=value`. For each realm file, the keys its JSON holds with a non-null value are read (`jq`, on stdin); the `-s` options are the stack's values of the keys it doesn't hold.
- Lines printed, per realm created: `Realm <realm>: brute-force settings from its export, the stack's for <keys>` (or `…, all of them` when it holds the ten), then `Realm <realm>: no brute-force detection, as its export says (README.md, "Brute-force protection")` when its export holds `bruteForceProtected: false`.
- On the demo host, before anything changes (with the checks of the realm exports, intent 0013): `--realm <file>: permanentLockout <value>, which would let whoever knows a user name lock that account for good: refused` (v3: `maxFailureWaitSeconds <value>, which would let whoever knows a user name lock that account for more than 15 minutes at a time`, `maxSecondaryAuthFailures <value>, which would let whoever knows its password lock that account for good with wrong second-factor codes`), then `On the demo host, a realm's export never locks an account for good, nor for more than 15 minutes at a time (README.md, "Brute-force protection"); nothing was registered.`, exit 1.
- Developer: registering immo in dev gives its realm 5 failures. Demo visitor: on the demo host, the realms created from now on lock as their exports say; one whose export turns the detection off has none.

## Points of attention

### PA-01: Which settings win

- Issue: the exports hold all ten settings (Keycloak exports them), so "the export decides" also lets an export turn the detection off, which 0010 prevented.
- Options: A) the export decides literally, the switch included / B) the export decides when it turns the detection on, the stack's otherwise / C) the stack's imposed, with a warning naming what it replaced.
- Recommendation: B (an application tunes its protection, can't drop it).
- Decider: product owner.
- Decision: A, 2026-10-30, Jérôme Wacongne: Faito's realm, created again, has no detection until its export turns it on, accepted knowingly.

### PA-02: An export that locks an account for good, on the demo host

- Issue: under PA-01 A, an export with `permanentLockout: true` registers without a word; on the public demo, whoever knows a user name could then lock that account for good (the review round, 2026-10-30).
- Options: A) leave it / B) one more line, as for the detection off / C) refuse it on the demo host.
- Recommendation: B (the rule kept, the fact said).
- Decider: product owner.
- Decision: C, 2026-10-30, Jérôme Wacongne (RQ-06, AC-06). A very long temporary lockout (`maxFailureWaitSeconds`) is not part of it.

### PA-03: A very long temporary lockout, and the second factor's lockout, on the demo host

- Issue: PA-02's C leaves two ways to lock an account on the public demo: a temporary lockout whose ceiling, `maxFailureWaitSeconds`, is very long, renewed by one failure at each of its ends; and `maxSecondaryAuthFailures`, after which Keycloak disables an account for good on wrong second-factor codes (found reading `DefaultBruteForceProtector`, 2026-10-30). The six exports hold 900 and 0.
- Options: A) leave them / B) a ceiling of 900 s, the exports' and the stack's value, and the second factor's lockout refused / C) a lower ceiling (10 s, say), the three applications' exports lowered first, or they are refused at their next registration on the demo host.
- Recommendation: B (no export refused today; each application stays free to go lower in its own export, PA-01 A; a lower ceiling stops no determined attacker, it only shortens the wait once the failures stop).
- Decider: product owner.
- Decision: B, 2026-10-30, Jérôme Wacongne ("Ok pour 900s", in answer to the recommendation that covered both settings) (RQ-07, AC-08). The PO's frame: the demo host only shows use cases, never hosts an acceptance-testing campaign, and can be redeployed from scratch at any time (README, "Demo host").

## Acceptance criteria

- **AC-01:** Given verif-lockout's export (detection off, 30 failures, `MULTIPLE`, the seven others absent), when `register-app.sh` creates the realm, then it holds those three values and the stack's seven others, the registration names the seven, and says the realm has no detection. (RQ-01, RQ-02, RQ-03)
- **AC-02:** Given a copy without any of the ten settings, when `register-app.sh --reset-realms` creates the realm, then it holds the stack's ten, the registration names all ten, and its user is locked after its 10th failure, not its 9th, and logs in again a minute later. (RQ-02, RQ-03, RQ-04)
- **AC-03:** Given the realm in Keycloak, when it is registered again without `--reset-realms`, then it is left as it is. (RQ-04)
- **AC-04:** The master realm has no detection, and the registration account may not change its settings (0010's AC-01 and AC-08, unchanged). (constraint)
- **AC-05:** README and `docs/migration.md` say that the export decides, the stack's values filling what it doesn't hold, that an export with the detection off registers without one, and that the demo host refuses one that locks an account for good, or for more than 15 minutes at a time. (RQ-05)
- **AC-06:** Given `INFRA_ENV=demo` and an export of an application that has a demo host whose `permanentLockout` is `true`, `"TRUE"` or `1`, or whose `attributes` hold `permanentLockout: "true"` (even beside a top-level `false`), when `register-app.sh` registers it, then it is refused, naming the file, the place and the value, before any docker call; with `false`, `null`, `"false"`, an attribute `"false"`, or without the setting, it goes past that check (a docker call); in dev, `true` goes past it. (RQ-06)
- **AC-07:** Given a copy without any of the ten settings at its top level, whose `attributes` hold `failureFactor: "3"`, when `register-app.sh --reset-realms` creates the realm, then it holds 3 failures, and the registration names the nine others as the stack's. (RQ-01, RQ-03)
- **AC-08:** Given `INFRA_ENV=demo` and an export whose `maxFailureWaitSeconds` is 901, or whose `attributes` hold `maxFailureWaitSeconds: "86400"` or `"nan"`, or whose `maxSecondaryAuthFailures` is 3, or whose `attributes` hold `maxSecondaryAuthFailures: "3"`, when `register-app.sh` registers it, then it is refused, naming the file, the place and the value, before any docker call; with 900, an attribute `"900"`, 0 or an attribute `"0"`, it goes past that check; in dev, an export holding `maxFailureWaitSeconds: 901` and `maxSecondaryAuthFailures: 3` goes past it. (RQ-07)

## Intent questions

None open.

## Change log

- v1, 2026-10-30: drafted and approved in the session (PA-01 decided).
- v2, 2026-10-30: PA-02, from the review round, decided C: RQ-06 and AC-06 added, RQ-05 and AC-05 extended; the realm's `attributes`, which Keycloak writes last, count as the export's (RQ-01, RQ-06, AC-07), found by the review of RQ-06's diff; approved in the session.
- v3, 2026-10-30: PA-03 decided B: RQ-07 and AC-08 added, the summary, the target behaviour's messages and AC-05 extended; approved in the session. Then, from the review of its diff, RQ-07 and AC-08 say which strings are a number (`"nan"` isn't).
