# Spec: On the demo host, an application's containers reach every shared service and every other application

- Intent: [0007](intent.md)
- Status: draft
- Version: 1
- Risk: high (rules: the isolation between applications, personal data — the demo visitors' mails and accounts, what a host exposes inside its Docker network; tech lead's agreement required)
- Policies applied: none yet; standing constraints: README design, `docs/migration.md`; c4-infra 0002 (deployment and registration as root-owned commands), 0003 (one compose base with overrides), 0004 (the registry names each application)
- Approved: —

## Summary

Each application's containers join a network of their own, to which the registration attaches the shared services the application uses; no two applications share a network. The command that starts an application's compose project refuses whatever would leave that isolation. Keycloak's database is on Keycloak's network only. On the demo host, Mailpit asks for its credentials itself, wherever it is reached from. An application keeps the same names and calls as today. Grafana LGTM is attached as it is: its telemetry stays readable and writable from every application's network, and the README says so (PA-2).

## Requirements

- REQ-1 Each application's containers join one network of their own, which no other application's container joins (PA-1 decided). (intent: proposed outcome)
- REQ-2 On that network, the shared services the application uses are reachable as today, by the same names: Caddy (with the shared host's alias, for the issuer), Keycloak (`keycloak:8080`, from which Keycloak reaches the application's gateway for back-channel logout), Mailpit's SMTP, RabbitMQ's AMQP and Grafana LGTM. (intent: constraint, success criterion)
- REQ-3 Keycloak's database is on a network that only Keycloak joins. (intent)
- REQ-4 On the demo host, Mailpit's web UI and API ask for the demo's Mailpit credentials themselves, whether they are reached through Caddy or from a container; in dev, Mailpit stays without authentication (0003 REQ-2). (intent)
- REQ-5 Registering an application creates its network when it is missing, named after its registry entry only (0004), and attaches to it the shared services of REQ-2, never Keycloak's database. They stay attached when the shared stack is restarted or recreated by its deployment, without registering the applications again. (intent; 0002 REQ-3: a registration acts only on what is the application's)
- REQ-6 What stays reachable and unprotected from an application's network is recorded in the README (PA-2 decided): Grafana LGTM's OTLP receivers accept any telemetry, so an application can write under another's name; its Prometheus, Tempo, Loki and Pyroscope ports answer without authentication, so an application can read every application's metrics, traces, logs and profiles; Keycloak's management port answers its health and metrics. (intent: open question)
- REQ-7 The README's design and `docs/migration.md` describe the application's network, which its compose project joins instead of `c4-infra`. (intent)
- REQ-8 The same topology applies in dev, where an application's containers join its network too (Tickee's LDAP server, which Keycloak federates). (intent: affected systems)
- REQ-9 The root-owned command that starts an application's compose project (0002 REQ-2) refuses a project that would leave its isolation: a network other than the application's own, `network_mode`, a container name or network alias outside `<app>.`, a service named after a shared service (`keycloak`, `mailpit`, `rabbitmq`, `grafana-lgtm`, `reverse-proxy`, the shared host's name), and what escapes a container altogether (privileged mode, the Docker socket, host paths outside the application's directory). (intent: proposed outcome)

## Out of scope

- The rest of what an application's deployment can do on the host (0002).
- The applications' processes on the workstation in dev, which reach the stack's ports on the loopback (0001).
- Keycloak's admin console, already public through Caddy behind its login.
- The applications' own networks (their databases stay on their compose project's network).

## Design

### Current behaviour

- `demo/compose.yml` and `compose.yml`: one network, `c4-infra` (`networks.default.name`), which every service joins, `keycloak-db` included; each application's containers join it too, with unique names (README, "What an application's deployment does"; `docs/migration.md` step 2). Nothing checks an application's compose file.
- Caddy carries the alias `${INFRA_HOST}` on that network, so that the applications reach the issuer through it; it reaches Keycloak as `keycloak:8080` (`demo/caddy/Caddyfile`).
- Mailpit: SMTP authentication (`MP_SMTP_AUTH`), no authentication of its UI and API on `8025`; the demo's `/mailpit/*` route asks for a basic authentication in Caddy.
- Keycloak serves plain HTTP on `8080` (`KC_HTTP_ENABLED`); the applications may call its token endpoint and admin API there (`KC_HOSTNAME_BACKCHANNEL_DYNAMIC`); it reaches each gateway at `http://<app>.gateway:7080` for back-channel logout; its management port `9000` serves health and metrics (`keycloak/Dockerfile`).
- Grafana LGTM (`grafana/otel-lgtm`) bundles OTLP receivers (4317, 4318), Grafana (3000, with its login), and Prometheus (9090), Tempo (3200), Loki and Pyroscope (4040), without authentication.
- In dev, Tickee's LDAP server joins `c4-infra` so that Keycloak federates it (`docs/migration.md`, Tickee).

### Behaviour per persona

- Demo visitor: another application's containers can neither read their mails nor reach the application they use; the telemetry of every application stays readable from each (PA-2).
- Application: the same names and calls; its compose project joins its own network; a compose file that leaves its isolation is refused at deployment.
- Demo operator: nothing more to run; the registration attaches the shared services.

### API and contracts

- An application's network: named after its registry entry (0004), the exact name settled in the plan.
- The shared services' names on it: unchanged (`keycloak`, `mailpit`, `rabbitmq`, `grafana-lgtm`, the shared host's name).
- The deployment command's refusals (REQ-9).

### User interface

None.

### Data

None.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| README design (unique container names; Caddy and Keycloak reach the applications by name) | REQ-2, REQ-7, REQ-9 |
| 0002 (deployment and registration as root-owned commands) | REQ-5 and REQ-9 are part of the commands it defines |
| 0003 (one compose base with overrides) | REQ-3, REQ-8: the networks are declared once |
| 0004 (the registry names each application) | REQ-5: one network per registry entry |

## Points of attention

### PA-1 How the applications are kept apart (decided)

- Issue: Docker doesn't isolate the containers of one network from each other; Keycloak and Caddy must still reach every application.
- Options: A one network per application, with the shared services attached to each by the registration / B the one `c4-infra` network, each service protecting itself (Mailpit's own authentication): the applications still reach each other's containers / C the one network, with firewall rules between containers (`DOCKER-USER` chain) on the host
- Recommendation: A: Docker's own isolation, in the compose files and the registration; B leaves every other application's ports open; C is host configuration outside the repository, easy to lose on a reinstall.
- Decides: tech lead (the mechanism), PO (the blast radius)
- Decision: A, one network per application (PO and tech lead, 2026-10-21)

### PA-2 Telemetry from an application's network (decided)

- Issue: in Grafana LGTM's container, the OTLP receivers accept any telemetry, and Prometheus, Tempo, Loki and Pyroscope answer without authentication: attaching it to an application's network gives that application the reading of every application's metrics, traces, logs and profiles (URLs, user ids), as well as writing under another's name.
- Options: A an OpenTelemetry collector as a relay, alone on the applications' networks, Grafana LGTM kept off them: no reading, writing under another's name still possible / B the same relay with a token per application: neither reading nor impersonation, a secret per application / C Grafana LGTM attached as it is: reading and writing open to every application, recorded in the README
- Recommendation: A: it closes the reading of personal data in traces and logs for one more container and no secret.
- Decides: PO (accepts the risk)
- Decision: C, Grafana LGTM attached as it is, the exposure recorded in the README (PO, 2026-10-21). First decided on a wrong premise (reading thought to need Grafana's login), then decided again with the facts.

## Acceptance criteria

Until the demo host exists and Hurura'a is migrated, AC-1 to AC-4 and AC-8 to AC-10 run on the workstation, with the demo override and stand-in containers named after Faito and Hurura'a (as 0003 AC-7).

- AC-1 Given Faito and Hurura'a deployed, then from a Faito container neither `hururaa.gateway` nor `keycloak-db` can be reached. (REQ-1, REQ-3)
- AC-2 From a Faito container on the demo host, `GET http://mailpit:8025/mailpit/api/v1/messages` without credentials gets `401`; through Caddy, `/mailpit/` still asks for them. (REQ-4)
- AC-3 From a Faito container, `keycloak:8080`, Mailpit's SMTP (with its credentials), RabbitMQ's AMQP (with Faito's user), Grafana LGTM's OTLP receivers and the shared host's name answer. A user logs in and out of Faito, a logout in Keycloak reaches Faito's gateway by back-channel, a verification mail arrives in Mailpit, an event is published, and Faito's traces show in Grafana. (REQ-2)
- AC-4 Given the shared stack recreated by its deployment, then AC-3 holds without registering Faito again. (REQ-5)
- AC-5 The README records the exposure of REQ-6, port by port. (REQ-6)
- AC-6 The README's design and `docs/migration.md` name the application's network, and no longer tell an application to join `c4-infra`. (REQ-7)
- AC-7 In dev, Tickee's LDAP server is on Tickee's network, Keycloak federates it, and a container on another application's network can't reach it. (REQ-8)
- AC-8 Given a Faito compose project with `network_mode: "container:c4-infra.keycloak"`, a service named `keycloak` or an alias `keycloak` on Faito's network, Hurura'a's network as an external one, `privileged: true`, or the Docker socket mounted, when Faito's deployment starts it, then each is refused before any container starts. (REQ-9)
- AC-9 From a Faito container, the shared services' ports that answer are those of REQ-2 and those REQ-6 lists, and no other. (REQ-2, REQ-6)
- AC-10 Given Faito registered, then the shared services of REQ-2 are attached to Faito's network, `keycloak-db` to Keycloak's only, and Hurura'a's network is unchanged. (REQ-5)

## Intent questions

- Does an application need another application's containers → no: none of the four does (`docs/migration.md` lists only the shared services and each application's own containers).
- What can't be protected inside the network → PA-2.

## Change log

- v1 — 2026-10-21 — first version
- v1 — 2026-10-21 — draft: coherence review (compose files checked at deployment, the whole of Grafana LGTM's and Keycloak's exposure, the network named from the registry only, how the criteria run before the demo host exists), PA-1 decided, PA-2 decided again with the facts
