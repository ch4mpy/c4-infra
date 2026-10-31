# Intent: register-app.sh replaces an application's brute-force settings with the stack's, without a word

- Author: Jérôme Wacongne (product owner, tech lead); drafted by the agent from the reading of Tickee and poc-immo-pf of 2026-10-30
- Kind: change
- Source: conversation (2026-10-30: immo's question "brute force 5 vs 10", handover of 2026-10-28)
- Spec needed: yes
- Status: delivered (2026-10-30)
- Opened: 2026-10-30
- Decided: 2026-10-30
- Supersedes: —
- Mode: bootstrap

## Problem

Since 0010, `register-app.sh` gives every realm it creates the stack's brute-force settings (a temporary lockout after 10 failures, at most 15 minutes), whatever its export says, and says only "brute-force protection set". An application that chose its own settings loses them without being told: immo's realm and Tickee's four realms ask for a lockout after 5 failures, and get 10 in dev and on the demo host. The application's team reads its export, not the realm Keycloak holds, and believes its setting applies.

## Proposed outcome

The application decides: each brute-force setting its export holds is kept as the export says; the stack's settings only fill the ones it doesn't hold; the registration says which came from the stack, and says so when the detection is off.

Success criterion: immo's realm, registered, locks an account after 5 failures; an export with none of these settings still gets the stack's.

## Affected users and systems

- Application (immo, Tickee, Faito; any application whose export holds these settings), Developer, Demo visitor (the demo accounts' lockout).
- Registration (`register-app.sh`), README ("Brute-force protection"), `docs/migration.md`.

## Constraints

- 0010: the master realm keeps no detection, and the registration account may not change its settings; a realm already in Keycloak keeps its own until it is imported again.

## Decided at acceptance (the product owner, 2026-10-30)

- The export decides literally, the detection's switch included: an export with `bruteForceProtected: false` registers without detection. Faito's export says so (Keycloak's default), so Faito's realm, created again, has no brute-force detection until Faito's export turns it on: accepted knowingly; Faito's own repository decides.
- Set aside: the stack's settings imposed with a warning; the stricter value of the two kept.
