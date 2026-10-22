# Spec: On the demo host, an application's containers reach every shared service and every other application

- Intent: [0007](intent.md)
- Status: draft
- Version: 1
- Risk: high (rules: the isolation between applications, personal data — the demo visitors' mails and accounts, what a host exposes inside its Docker network; tech lead's agreement required)
- Policies applied: none yet; standing constraints: README design, `docs/migration.md`; c4-infra 0002 (registration as a root-owned command), 0003 (one compose base with overrides), 0004 (the registry names each application)
- Approved: —

## Summary

Each application's containers join a network of their own, to which the registration attaches the shared services the application uses; no two applications share a network. Keycloak's database is on Keycloak's network only. On the demo host, Mailpit asks for its credentials itself, wherever it is reached from. An application keeps the same names and calls as today. Telemetry stays unauthenticated inside each application's network (PA-2).

## Requirements

- REQ-1 Each application's containers join one network of their own, which no other application's container joins (PA-1). (intent: proposed outcome)
- REQ-2 On that network, the shared services the application uses are reachable as today, by the same names: Caddy (with the shared host's alias, for the issuer), Keycloak (`keycloak:8080`, from which Keycloak reaches the application's gateway for back-channel logout), Mailpit's SMTP, RabbitMQ's AMQP and Grafana LGTM's OTLP receivers. (intent: constraint, success criterion)
- REQ-3 Keycloak's database is on a network that only Keycloak joins. (intent)
- REQ-4 On the demo host, Mailpit's web UI and API ask for the demo's Mailpit credentials themselves, whether they are reached through Caddy or from a container; in dev, Mailpit stays without authentication (0003 REQ-2). (intent)
- REQ-5 Registering an application creates its network when it is missing and attaches the shared services to it. They stay attached when the shared stack is restarted or recreated by its deployment, without registering the applications again. (intent)
- REQ-6 What stays unprotected inside an application's network is recorded in the README: Grafana LGTM's OTLP receivers accept any telemetry, so an application can write telemetry under another's name; reading it needs Grafana's login (PA-2). (intent: open question)
- REQ-7 The README's design and `docs/migration.md` describe the application's network, which its compose project joins instead of `c4-infra`. (intent)
- REQ-8 The same topology applies in dev, where an application's containers join its network too (Tickee's LDAP server, which Keycloak federates). (intent: affected systems)

## Out of scope

- What an application's deployment can do on the host (0002).
- The applications' processes on the workstation in dev, which reach the stack's ports on the loopback (0001).
- Keycloak's admin console, already public through Caddy behind its login.
- The applications' own networks (their databases stay on their compose project's network).

## Design

### Current behaviour

- `demo/compose.yml` and `compose.yml`: one network, `c4-infra` (`networks.default.name`), which every service joins, `keycloak-db` included; each application's containers join it too, with unique names (README, "What an application's deployment does"; `docs/migration.md` step 2).
- Caddy carries the alias `${INFRA_HOST}` on that network, so that the applications reach the issuer through it.
- Mailpit: SMTP authentication (`MP_SMTP_AUTH`), no authentication of its UI and API on `8025`; the demo's `/mailpit/*` route asks for a basic authentication in Caddy.
- Keycloak serves plain HTTP on `8080` (`KC_HTTP_ENABLED`); the applications may call its token endpoint and admin API there (`KC_HOSTNAME_BACKCHANNEL_DYNAMIC`); it reaches each gateway at `http://<app>.gateway:7080` for back-channel logout.
- In dev, Tickee's LDAP server joins `c4-infra` so that Keycloak federates it (`docs/migration.md`, Tickee).

### Behaviour per persona

- Demo visitor: another application's containers can't read their mails nor reach the application they use.
- Application: the same names and calls; its compose project joins its own network.
- Demo operator: nothing more to run; the registration attaches the shared services.

### API and contracts

- An application's network: named after its registry entry (0004), the exact name settled in the plan.
- The shared services' names on it: unchanged (`keycloak`, `mailpit`, `rabbitmq`, `grafana-lgtm`, the shared host's name).

### User interface

None.

### Data

None.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| README design (unique container names; Caddy and Keycloak reach the applications by name) | REQ-2, REQ-7 |
| 0002 (registration as a root-owned command) | REQ-5 is part of the registration it runs |
| 0003 (one compose base with overrides) | REQ-3, REQ-8: the networks are declared once |
| 0004 (the registry names each application) | REQ-5: one network per registry entry |

## Points of attention

### PA-1 How the applications are kept apart (to decide)

- Issue: Docker doesn't isolate the containers of one network from each other; Keycloak and Caddy must still reach every application.
- Options: A one network per application, with the shared services attached to each by the registration / B the one `c4-infra` network, each service protecting itself (Mailpit's own authentication): the applications still reach each other's containers / C the one network, with firewall rules between containers (`DOCKER-USER` chain) on the host
- Recommendation: A: Docker's own isolation, in the compose files and the registration; B leaves every other application's ports open; C is host configuration outside the repository, easy to lose on a reinstall.
- Decides: tech lead (the mechanism), PO (the blast radius)
- Decision: to decide

### PA-2 Telemetry inside an application's network (to decide)

- Issue: Grafana LGTM's OTLP receivers have no authentication; an application can send telemetry under another's service name. Reading it needs Grafana's login.
- Options: A accepted on the demo, recorded in the README / B an OpenTelemetry collector in front of the receivers, with a token per application
- Recommendation: A: the demo's telemetry drives no decision and holds no secret; B adds a service and a secret per application.
- Decides: PO (accepts the risk)
- Decision: to decide

## Acceptance criteria

- AC-1 Given Faito and Hurura'a deployed on the demo host, then from a Faito container neither `hururaa.gateway` nor `keycloak-db` can be reached. (REQ-1, REQ-3)
- AC-2 From a Faito container on the demo host, `GET http://mailpit:8025/mailpit/api/v1/messages` without credentials gets `401`; through Caddy, `/mailpit/` still asks for them. (REQ-4)
- AC-3 From a Faito container, `keycloak:8080`, Mailpit's SMTP (with its credentials), RabbitMQ's AMQP (with Faito's user), the OTLP receivers and the shared host's name answer. A user logs in and out of Faito, a logout in Keycloak reaches Faito's gateway by back-channel, a verification mail arrives in Mailpit, an event is published, and Faito's traces show in Grafana. (REQ-2)
- AC-4 Given the shared stack recreated by its deployment, then AC-3 holds without registering Faito again. (REQ-5)
- AC-5 The README records that the OTLP receivers accept any telemetry inside each application's network. (REQ-6)
- AC-6 The README's design and `docs/migration.md` name the application's network, and no longer tell an application to join `c4-infra`. (REQ-7)
- AC-7 In dev, Tickee's LDAP server is on Tickee's network, Keycloak federates it, and a container on another application's network can't reach it. (REQ-8)

## Intent questions

- Does an application need another application's containers → no: none of the four does (`docs/migration.md` lists only the shared services and each application's own containers).
- What can't be protected inside the network → PA-2.

## Change log

- v1 — 2026-10-21 — first version
