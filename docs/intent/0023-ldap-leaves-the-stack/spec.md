# Spec: The stack still documents and tests an LDAP user federation no application needs

- Intent: [0023](intent.md)
- Status: approved
- Version: 1
- Risk: standard (PA-03: the isolation and the authentication flows are unchanged)
- Policies applied: none yet; standing constraints: README's design ("One network per application", intent 0007), CLAUDE.md "Verification"
- Approved: 2026-10-28, Jérôme Wacongne (product owner, and tech lead for PA-02 and PA-03; in the drafting session; every point of attention decided)

## Summary

LDAP leaves the stack: the stack provides, runs and monitors no directory. A realm may still federate its users, with a directory its application runs and maintains itself, on its own network; README and the migration guide say so, Tickee's `tenant2` keeping its LDAP server as Tickee's own container. The dev isolation test proves 0007's dev topology with an HTTP stand-in instead of an LDAP server.

## Requirements

- **RQ-01:** README's "One network per application" names, as the example of an application's container the shared services reach, its gateway (which Keycloak calls for back-channel logout), and says that a realm may federate its users with a directory the application runs and maintains itself, on its own network, the stack providing none. (intent: outcome; constraint, 0007's RQ-08 with another example; PA-01)
- **RQ-02:** `docs/migration.md`'s generic step names the containers the shared services reach (a gateway; a directory a realm federates) as the project's own, on its network, which the project maintains; Tickee's section keeps `tenant2`'s federation, its `ldap2` server being Tickee's own container on `c4-infra.tickee`, which Tickee runs, monitors and upgrades. (intent: outcome; PA-01, its follow-up on `tenant2`)
- **RQ-03:** In dev, a container on Tickee's network (`c4-infra.tickee`) is reached by Keycloak and can't be reached from another application's network, by name nor by address, proven with an HTTP stand-in rather than an LDAP server; it replaces 0007's AC-07. (intent: outcome, the dev isolation stays proven; PA-02)
- **RQ-04:** A registration keeps accepting a realm that federates its users: no check refuses it (PA-01). (intent: open question)
- **RQ-05:** No test, script or example of the stack starts, configures or depends on an LDAP server; README and the guide mention one only as an application's own directory. (intent: outcome)

## Out of scope

- Tickee's own repository (its realm export, its compose file, its `ldap2` server): the guide says what is Tickee's.
- Monitoring an application's directory: the application's.
- 0007's other criteria and its topology: unchanged.

## Design

### Current behaviour

- `README.md:81-83`: "in dev, those the shared services must reach, such as Tickee's LDAP server" join the application's network.
- `docs/migration.md:120`: "Another container of the project that the shared Keycloak must reach (an LDAP server of a user federation) joins the project's own network"; `:145`: "(gateway, API, frontend, an LDAP server)"; `:278-284`: `tenant2` federates `ldap://tickee.ldap-tenant2:389`, its `ldap2` container started by Tickee's compose on `c4-infra.tickee`, in dev as on the demo host.
- `tests/0007-dev.sh:157-185` (part `tickee`, 0007's AC-07): Tickee registered (its network only), `osixia/openldap:1.5.0` started as `tickee.ldap-standin` on `c4-infra.tickee`, Keycloak's `testLDAPConnection` retried until it succeeds, a control from `c4-infra.tickee`, two negative checks from `c4-infra.faito` (by name, by address). The image opens port 389, closes it a second later and opens it again (measured 2026-10-28): the control fails now and then (intent 0021, abandoned), and the negative checks can pass in that gap for the wrong reason.
- `tests/0007-isolation.stand-in.sh:161-163` proves on the demo side that Keycloak reaches an application's gateway (`exec 3<>/dev/tcp/faito.gateway/7080` in Keycloak's container), as back-channel logout does.
- `register-app.sh:255-321` checks a realm export's client profiles and realm attributes; none of its checks reads user federations. On the demo host, neither `tickee` nor `tenant2` exists (their discovery: `404`, 2026-10-28).

### Behaviour per persona

- Developer: reads that the stack provides no directory; a project whose realm federates users runs and maintains its directory itself, on its own network; the dev isolation test starts no LDAP server.
- Application (Tickee): `tenant2` keeps federating `ldap2`, Tickee's own container.

### API and contracts

- `register-app.sh`: unchanged.

### Data

None.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| README "One network per application" (0007) | RQ-01, RQ-03: the topology unchanged, its dev proof without LDAP |
| CLAUDE.md "Verification" | RQ-03: proven by a test of the suite |

## Points of attention

### PA-01: Refuse a realm that federates users

- Issue: removing LDAP from the stack leaves open whether a realm may still federate its users.
- Options: A) a registration refuses every user federation of a realm export / B) LDAP only / C) no refusal, the docs only.
- Recommendation: A.
- Decides: PO
- Decision: none of them as written: a realm may federate its users, and its application then runs and maintains the directory's containers itself, on its own network; the stack provides, runs and monitors none, and no registration refuses a federation (Jérôme Wacongne, PO, 2026-10-28). Follow-up, the same session: Tickee's `tenant2` keeps its LDAP server, as Tickee's own container maintained by Tickee, which departs knowingly from the intent's outcome ("moves `tenant2`'s users into Keycloak's database").

### PA-02: What replaces AC-07's check

- Issue: AC-07 proves 0007's dev topology with an LDAP server; its replacement must keep the proof without one.
- Options: A) an HTTP stand-in on `c4-infra.tickee` (as Tickee's gateway would be), which Keycloak reaches (`/dev/tcp`, as back-channel logout does, as `0007-isolation.stand-in` checks it) and a container on `c4-infra.faito` can't, by name nor by address; ready when it starts / B) no replacement: the `networks` part's membership checks stand alone.
- Recommendation: A.
- Decides: tech lead
- Decision: A, an HTTP stand-in (Jérôme Wacongne, tech lead, 2026-10-28)

### PA-03: Risk level

- Issue: the change replaces the dev proof of the isolation between applications.
- Options: A) high / B) standard (the isolation itself and the authentication flows are unchanged).
- Recommendation: A, high.
- Decides: tech lead
- Decision: B, standard (Jérôme Wacongne, tech lead, 2026-10-28)

## Acceptance criteria

- **AC-01:** Given README and `docs/migration.md`, then README's example of a container the shared services reach is an application's gateway, and README says that a federated directory is the application's own container, on its network, maintained by it, the stack providing none; the guide's generic step says the same, and Tickee's section presents `ldap2` as Tickee's container, maintained by Tickee. (RQ-01, RQ-02, RQ-04)
- **AC-02:** Given Tickee registered in dev and an HTTP stand-in on `c4-infra.tickee`, then Keycloak reaches it, and a container on `c4-infra.faito` can't, by name nor by address; `tests/0007-dev.sh` starts no LDAP server. (RQ-03)
- **AC-03:** Given the stack, then `git grep -n -i ldap -- . ':!docs/intent'` finds no test, script or example that starts, configures or depends on an LDAP server, and in README and the guide only an application's own directory. (RQ-05)

## Intent questions

- Whether a registration refuses a realm that federates users → PA-01: no; the application maintains its directory.
- What replaces AC-07's check → PA-02: an HTTP stand-in.

## Change log

- v1 — 2026-10-28 — first version; approved: PA-01 (no refusal, the application's own directory; `tenant2` keeps its LDAP server, Tickee's), PA-02 A, PA-03 B
