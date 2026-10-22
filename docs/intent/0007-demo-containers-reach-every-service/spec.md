# Spec: On the demo host, an application's containers reach every shared service and every other application

- Intent: [0007](intent.md)
- Status: approved
- Version: 1
- Risk: high (rules: the isolation between applications, personal data — the demo visitors' mails and accounts, what a host exposes inside its Docker network; tech lead's agreement required)
- Policies applied: none yet; standing constraints: README design, `docs/migration.md`; c4-infra 0002 (deployment and registration as root-owned commands), 0003 (one compose base with overrides), 0004 (the registry names each application)
- Approved: 2026-10-21, Jérôme Wacongne (PO, and tech lead for the high risk)

## Summary

Each application's containers join a network of their own, to which the registration attaches the shared services the application uses; no two applications share a network. The command that starts an application's compose project refuses whatever would leave that isolation. Keycloak's database is on Keycloak's network only. On the demo host, Mailpit asks for its credentials itself, wherever it is reached from. An application keeps the same names and calls as today. Grafana LGTM is attached as it is: its telemetry stays readable and writable from every application's network, and the README says so (PA-2). RabbitMQ's Erlang ports stay inside its container, and the shared services' metrics ports are recorded (PA-3).

## Requirements

- REQ-1 Each application's containers join one network of their own, which no other application's container joins (PA-1 decided). (intent: proposed outcome)
- REQ-2 On that network, the shared services the application uses are reachable as today, by the same names: Caddy (with the shared host's alias, for the issuer), Keycloak (`keycloak:8080`, from which Keycloak reaches the application's gateway for back-channel logout), Mailpit's SMTP, RabbitMQ's AMQP and Grafana LGTM. (intent: constraint, success criterion)
- REQ-3 Keycloak's database is on a network that only Keycloak joins. (intent)
- REQ-4 On the demo host, Mailpit's web UI and API ask for the demo's Mailpit credentials themselves, whether they are reached through Caddy or from a container; in dev, Mailpit stays without authentication (0003 REQ-2). (intent)
- REQ-5 Registering an application creates its network when it is missing, named after its registry entry only (0004), and attaches to it the shared services of REQ-2, never Keycloak's database. They stay attached when the shared stack is restarted or recreated by its deployment, without registering the applications again. (intent; 0002 REQ-3: a registration acts only on what is the application's)
- REQ-6 What stays reachable from an application's network beyond REQ-2 and REQ-4 is recorded in the README, port by port:
  - Grafana LGTM's OTLP receivers (4317, 4318) accept any telemetry, so an application can write under another's name (PA-2 decided);
  - its Prometheus (9090), Tempo (3200), Loki (3100) and Pyroscope (4040) ports answer without authentication, so an application can read every application's metrics, traces, logs and profiles (PA-2 decided);
  - Keycloak's management port (9000) answers its health and metrics, and RabbitMQ's Prometheus port (15692) its metrics if the image enables them (PA-3 decided).

  (intent: open question)
- REQ-7 The README's design and `docs/migration.md` describe the application's network, which its compose project joins instead of `c4-infra`. (intent)
- REQ-8 The same topology applies in dev, where an application's containers join its network too (Tickee's LDAP server, which Keycloak federates). (intent: affected systems)
- REQ-9 The root-owned command that starts an application's compose project (0002 REQ-2) refuses a project that would leave its isolation: a network other than the application's own, `network_mode`, a published port (only Caddy publishes on the host), a container name or network alias outside `<app>.`, a service named after a shared service (`keycloak`, `mailpit`, `rabbitmq`, `grafana-lgtm`, `reverse-proxy`, the shared host's name), and what escapes a container altogether (privileged mode, the Docker socket, host paths outside the application's directory). The last group is what 0002 REQ-1 also forbids: this check is the one that enforces it. (intent: proposed outcome)
- REQ-10 RabbitMQ's epmd (4369) and Erlang distribution (25672) listen on its container's loopback only: its tools (`rabbitmqctl`, its healthcheck, the registration's `docker exec`) run inside the container (PA-3 decided). On the demo host, RabbitMQ serves no management API (15672), as 0003 REQ-2 keeps it dev-only. (intent: proposed outcome)

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
- Grafana LGTM (`grafana/otel-lgtm`) bundles OTLP receivers (4317, 4318), Grafana (3000, with its login), and Prometheus (9090), Tempo (3200), Loki (3100) and Pyroscope (4040), without authentication.
- RabbitMQ (`rabbitmq:4.3.5` on the demo host, `rabbitmq:4.3.5-management` in dev) listens for AMQP (5672), epmd (4369) and the Erlang distribution (25672), serves Prometheus metrics (15692) when its plugin is enabled (to confirm on the image), and in dev its management API (15672).
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

### PA-3 The other ports of the attached shared services (decided)

- Issue: besides what REQ-2 needs, Keycloak's management port (9000: health and metrics) and RabbitMQ's epmd (4369), Erlang distribution (25672, behind its cookie: a leaked cookie runs code in RabbitMQ) and Prometheus metrics (15692, if enabled) answer from every network they are attached to.
- Options: A epmd and the distribution on RabbitMQ's container loopback, the metrics ports recorded in the README / B everything recorded, nothing closed / C A, plus the metrics disabled (Keycloak's and RabbitMQ's), which nothing reads today
- Recommendation: A: closes the one port that leads to code execution, for two settings; the metrics hold no personal data.
- Decides: PO (accepts the risk), tech lead (the mechanism)
- Decision: A, epmd and the distribution on the container's loopback, the metrics recorded (PO and tech lead, 2026-10-21)

## Acceptance criteria

Until the demo host exists and Hurura'a is migrated, AC-1, AC-2, AC-8 to AC-11 and the reachability part of AC-3 and AC-4 run on the workstation, with the demo override and stand-in containers named after Faito and Hurura'a (as 0003 AC-7). The end-to-end part of AC-3 and AC-4 (login, back-channel logout, mail, event, traces) runs with Faito's first demo deployment.

- AC-1 Given Faito and Hurura'a deployed, then from a Faito container neither `hururaa.gateway` nor `keycloak-db` can be reached. (REQ-1, REQ-3)
- AC-2 From a Faito container on the demo host, `GET http://mailpit:8025/mailpit/api/v1/messages` without credentials gets `401`; through Caddy, `/mailpit/` still asks for them. (REQ-4)
- AC-3 From a Faito container, `keycloak:8080`, Mailpit's SMTP (with its credentials), RabbitMQ's AMQP (with Faito's user), Grafana LGTM's OTLP receivers and the shared host's name answer. A user logs in and out of Faito, a logout in Keycloak reaches Faito's gateway by back-channel, a verification mail arrives in Mailpit, an event is published, and Faito's traces show in Grafana. (REQ-2)
- AC-4 Given the shared stack recreated by its deployment, then AC-3 holds without registering Faito again. (REQ-5)
- AC-5 The README records the exposure of REQ-6, port by port. (REQ-6)
- AC-6 The README's design and `docs/migration.md` name the application's network, and no longer tell an application to join `c4-infra`. (REQ-7)
- AC-7 In dev, Tickee's LDAP server is on Tickee's network, Keycloak federates it, and a container on another application's network can't reach it. (REQ-8)
- AC-8 Given a Faito compose project with any one of: `network_mode: "container:c4-infra.keycloak"`; a service named `keycloak`; an alias `keycloak` or `hururaa.gateway` on Faito's network; `container_name: hururaa.gateway`; Hurura'a's network as an external one; `ports: ["7080:7080"]`; `privileged: true`; the Docker socket, or a host path outside Faito's directory, mounted — when Faito's deployment starts it, then it is refused before any container starts. (REQ-9)
- AC-9 From a Faito container, the shared services' ports that answer are those of REQ-2, Mailpit's UI and API (answering `401`, REQ-4) and those REQ-6 lists, and no other: in particular not RabbitMQ's 4369 and 25672, nor its 15672 on the demo host. (REQ-2, REQ-4, REQ-6, REQ-10)
- AC-11 Given the registration and RabbitMQ's healthcheck run after REQ-10, then `rabbitmqctl` inside the container still imports a user's definitions and the healthcheck still reports RabbitMQ healthy. (REQ-10)
- AC-10 Given Faito registered, then the shared services of REQ-2 are attached to Faito's network, `keycloak-db` to Keycloak's only, and Hurura'a's network is unchanged. (REQ-5)

## Intent questions

- Does an application need another application's containers → no: none of the four does (`docs/migration.md` lists only the shared services and each application's own containers).
- What can't be protected inside the network → PA-2.

## Change log

- v1 — 2026-10-21 — first version
- v1 — 2026-10-21 — draft: coherence review (compose files checked at deployment, the whole of Grafana LGTM's and Keycloak's exposure, the network named from the registry only, how the criteria run before the demo host exists), PA-1 decided, PA-2 decided again with the facts
- v1 — 2026-10-21 — draft: second coherence review (published ports and other applications' names refused, Mailpit and RabbitMQ in the port check, RabbitMQ's other ports recorded, end-to-end criteria with Faito's first demo deployment)
- v1 — 2026-10-21 — draft: third coherence review (REQ-6 credits each port to the decision that covers it, RabbitMQ's Erlang ports closed and no management API on the demo host, AC-9 back to a fixed list), PA-3 decided
- v1 — 2026-10-21 — approved: every point of attention decided; tech lead's agreement for the high risk (Jérôme Wacongne, PO and tech lead)
