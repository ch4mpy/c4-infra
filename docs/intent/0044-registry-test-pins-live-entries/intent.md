# Intent: The registry's test pins the applications' real entries

- Author: Jérôme Wacongne (product owner, tech lead); drafted by the agent from the handover of 2026-10-30
- Kind: change
- Source: conversation (handover, "Left open": `tests/0004-registry.sh` still pins other live data of `registry.txt`)
- Spec needed: no
- Status: planned
- Opened: 2026-10-30
- Decided: 2026-10-30
- Supersedes: —
- Mode: bootstrap

## Problem

`tests/0004-registry.sh` checks `registry.sh`'s behaviour on the real `registry.txt`: Tickee's whole line, the fields `registry.sh entry tickee` prints, Faito's entry, the four first applications each present. An application that changes its own line (a realm, a theme, its demo host: 0045 changes immo's) breaks the stack's test, though `registry.sh` is right. 0018 removed one such pin (the count of entries) for the same reason.

## Proposed outcome

The test checks that the real registry is valid, and checks `registry.sh`'s reading of an entry on a fixture of its own: no check names an application's real values.

Success criterion: changing an application's line of `registry.txt` to other valid values leaves `tests/0004-registry.sh` passing.

## Affected users and systems

- Developer (the test suite), `tests/0004-registry.sh`, `tests/fixtures/0004/`.

## Constraints

- Each behaviour the removed checks proved (an entry's seven fields, `entry`'s output) is still proved, on the fixture.
