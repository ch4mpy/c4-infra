# Intent: The dev isolation test's LDAP control check fails now and then

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: bug
- Source: conversation (verification of 0017, 2026-10-28)
- Spec needed: no
- Status: accepted
- Opened: 2026-10-28
- Decided: 2026-10-28
- Supersedes: —
- Mode: bootstrap

## Problem

`tests/0007-dev.sh`'s `tickee` part starts an LDAP stand-in (`osixia/openldap:1.5.0`, as `tickee.ldap-standin`) on Tickee's network, checks that Keycloak connects to it (AC-07 of 0007), then runs a control: `from c4-infra.tickee, tickee.ldap-standin:389 answers` (`nc -z -w 3` from a fresh container on that network).

- Observed: the control failed in 0017's proof run (`--all` on 1502732), and in one of two runs of the test alone on the same commit, right after Keycloak's connection passed; the other run passed every check.
- Expected: the control passes whenever the LDAP stand-in is up on Tickee's network.
- Not reproduced elsewhere: from 20 fresh containers on `c4-infra.faito`, `reverse-proxy` resolved and `nc -z -w 3 reverse-proxy 443` answered 20 times out of 20.
- Environment: Ubuntu workstation, Docker Desktop 29.6.1, 2026-10-28.

A control that fails at random makes the verification red with no defect behind it; 0017 was delivered with this `KO` (product owner, 2026-10-28).

## Proposed outcome

The control passes on every run where the stack and the LDAP stand-in work, and still fails when the stand-in can't be reached from Tickee's network.

## Affected users and systems

- Personas: Developer (runs the verification)
- Modules / systems: the dev isolation test (`tests/0007-dev.sh`)

## Constraints

- The control keeps checking reachability from Tickee's network, and the checks that a container on another network can't reach the stand-in stay as they are.

## Open questions

- *Suggested solution*: `osixia/openldap` restarts `slapd` after its first configuration, so the control may hit that restart; wait until the stand-in is ready before the checks — the plan measures it.
