# Spec: register-app.sh replaces an application's brute-force settings with the stack's, without a word

- Intent: [0041](intent.md)
- Status: approved
- Version: 1
- Risk: high (authentication: the brute-force protection of the applications' realms, in dev and on the demo host)
- Policies applied: none yet; standing constraints: 0010 (the master realm without detection, the registration account unable to change it; a realm already in Keycloak kept as it is), CLAUDE.md
- Approved: 2026-10-30, Jérôme Wacongne (PO, also tech lead; in the session, PA-01 decided)

## Summary

`register-app.sh` stops imposing the stack's brute-force settings on a realm it creates: each setting the export holds is kept as the export says, the detection's switch included; the stack's value fills each one it doesn't hold; the registration names the settings it filled, and says when the realm has no detection. Changes 0010's RQ-01 as to the applications' realms ("whatever its export says"); the rest of 0010 holds.

## Requirements

- **RQ-01:** A realm `register-app.sh` creates keeps each of the ten brute-force settings its export holds (`bruteForceProtected`, `permanentLockout`, `maxTemporaryLockouts`, `failureFactor`, `bruteForceStrategy`, `waitIncrementSeconds`, `maxFailureWaitSeconds`, `maxDeltaTimeSeconds`, `quickLoginCheckMilliSeconds`, `minimumQuickLoginWaitSeconds`), as the export says; a setting the export gives as `null` counts as not held. (intent: proposed outcome; PA-01)
- **RQ-02:** Each setting the export doesn't hold takes the stack's value (0010's: detection on, no permanent lockout, no limit of temporary lockouts, 10 failures, linear, 60 s more per failure, at most 900 s, failures forgotten after 43200 s, quick logins under 1000 ms locking 60 s). (intent: proposed outcome)
- **RQ-03:** For each realm it creates, the registration prints one line naming the settings it took from the stack, or saying that the export holds them all; and one more when the realm has no detection (`bruteForceProtected: false` in its export). (intent: problem, "without a word")
- **RQ-04:** A realm already in Keycloak is left as it is, as today; `--reset-realms` creates it again under RQ-01 to RQ-03. (0010, constraint)
- **RQ-05:** README ("Brute-force protection") and `docs/migration.md` state the rule, its consequence for an export with the detection off, and how an application sets its own. (intent: proposed outcome)

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
- Developer: registering immo in dev gives its realm 5 failures. Demo visitor: on the demo host, the realms created from now on lock as their exports say; one whose export turns the detection off has none.

## Points of attention

### PA-01: Which settings win

- Issue: the exports hold all ten settings (Keycloak exports them), so "the export decides" also lets an export turn the detection off, which 0010 prevented.
- Options: A) the export decides literally, the switch included / B) the export decides when it turns the detection on, the stack's otherwise / C) the stack's imposed, with a warning naming what it replaced.
- Recommendation: B (an application tunes its protection, can't drop it).
- Decider: product owner.
- Decision: A, 2026-10-30, Jérôme Wacongne: Faito's realm, created again, has no detection until its export turns it on, accepted knowingly.

## Acceptance criteria

- **AC-01:** Given verif-lockout's export (detection off, 30 failures, `MULTIPLE`, the seven others absent), when `register-app.sh` creates the realm, then it holds those three values and the stack's seven others, the registration names the seven, and says the realm has no detection. (RQ-01, RQ-02, RQ-03)
- **AC-02:** Given a copy without any of the ten settings, when `register-app.sh --reset-realms` creates the realm, then it holds the stack's ten, the registration names all ten, and its user is locked after its 10th failure, not its 9th, and logs in again a minute later. (RQ-02, RQ-03, RQ-04)
- **AC-03:** Given the realm in Keycloak, when it is registered again without `--reset-realms`, then it is left as it is. (RQ-04)
- **AC-04:** The master realm has no detection, and the registration account may not change its settings (0010's AC-01 and AC-08, unchanged). (constraint)
- **AC-05:** README and `docs/migration.md` say that the export decides, the stack's values filling what it doesn't hold, and that an export with the detection off registers without one. (RQ-05)

## Intent questions

None open.

## Change log

- v1, 2026-10-30: drafted and approved in the session (PA-01 decided).
