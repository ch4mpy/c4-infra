# Spec: The demo host doesn't bound the logs of an application's containers

- Intent: [0026](intent.md)
- Status: approved
- Version: 1
- Risk: high (rules: the isolation between applications, the change touches `demo/c4-app`'s model check, 0007's gate, and PA-03 B would put every container's output within every application's reach; personal data, how long Loki keeps logs that carry user ids (README, "Reachable from an application's network"); tech lead's agreement required)
- Policies applied: none yet; standing constraints: README design (one compose base, dev and demo alike) and "Accounts", 0002 (accounts outside the `docker` group, one root-owned command), 0007 (one network per application, the allowlist; PA-02 C, Grafana LGTM attached as it is), 0011's accepted risk (a leaked deployment key)
- Approved: 2026-10-28, Jérôme Wacongne (product owner, and tech lead for the high risk; every point of attention decided as recommended)

## Summary

On the demo host, every container an application starts through `sudo c4-app up` keeps a bounded log, whatever its compose file says: the application still can't set `logging`, and Docker's unrotated default no longer applies to it. The shared stack's Loki deletes what it receives after a set retention. Where the bound is set (PA-01), its size (PA-02), how an application's logs reach Loki (PA-03), the retention (PA-04) and the stack's own services' setting (PA-05) are the product owner's and tech lead's.

## Requirements

- **RQ-01:** On the demo host, each container of an application's compose project keeps at most PA-02's bound of standard output and error, the oldest lines dropped first. (intent: outcome, problem)
- **RQ-02:** An application can't lift or change that bound from its files: `sudo c4-app up` and `pull` refuse a service's `logging`, naming the service and the key, and saying that the host bounds it (PA-01 B: accepted within the bound only). (intent: outcome, "whatever the application sets")
- **RQ-03:** An application's containers created before the change get the bound at its next `sudo c4-app up` after the stack's deployment, its files unchanged. (intent: outcome)
- **RQ-04:** The operator still reads a container's recent output with `docker logs` and `docker compose logs`. (intent: Demo operator)
- **RQ-05:** The stack's own services keep a bounded log, in dev as on the demo host (PA-05). (intent: problem)
- **RQ-06:** Loki deletes what it holds once older than PA-04's retention; the setting survives a restart and an image upgrade, and the README states it. (intent: outcome, "kept for a bounded time")
- **RQ-07:** The README states how long traces and metrics are kept, pinned per PA-04. (intent: problem, Grafana LGTM's volume kept with no retention set)
- **RQ-08:** No application's account joins the `docker` group or gains a command; no container reachable from an application's network gains a mount of Docker's files or another application's logs beyond what 0007 PA-02 C records (what each application exports to Grafana LGTM itself). (intent: constraint)
- **RQ-09:** The README ("Accounts", "Day to day", "Reachable from an application's network") and docs/migration.md state the bound, that `logging` is the host's, the retention, and how an application sends its logs to Loki (PA-03). (intent: affected systems)

## Out of scope

- A bound on Loki's volume by size: its filesystem retention is by time only; a burst within the retention still grows it.
- What a container writes elsewhere: files in its writable layer, its volumes, its database's own log files.
- An application reading its own Docker logs (it is outside the `docker` group): a `c4-app` command would be a new intent.
- The workstation's Docker Desktop and the applications' dev compose projects; Grafana LGTM's exposure (0007 PA-02 C stands).

## Design

### Current behaviour

- `demo/c4-app:187-193`: `logging` is not in the service allowlist; `:228-229` refuses it (`service <s>: logging is not allowed (outside the isolation allowlist …)`). The application's containers get the daemon's default.
- `demo/vps-bootstrap.sh:66-82` installs Docker from its repository and writes no `/etc/docker/daemon.json`: the default driver is `json-file`, and "by default, no log-rotation is performed" (Docker, "Configure logging drivers").
- `compose.yml:12-18`: the anchor `default-logging`, `json-file` 10m × 3, referenced by every stack service (`:56`, `:84`, `:111`, `:148`, `:185`, `:206`, `:240`): 30 MB per container at most.
- `grafana-lgtm` (`compose.yml:236-260`), `grafana/otel-lgtm:0.32.0`, Loki 3.7.6: the image's `loki-config.yaml` (tag v0.32.0) sets no `limits_config` nor `compactor`; Loki's defaults are `-compactor.retention-enabled=false` and `-store.retention=0s` (loki v3.7.6 `pkg/compactor/config.go:54`, `pkg/validation/limits.go:426-427`): nothing is ever deleted from `/data/loki`, on `grafana_data` (`:258`). Its `run-loki.sh` appends `LOKI_EXTRA_ARGS` (`compose.yml:253`) after the config: `-compactor.retention-enabled=true -store.retention=<d> -compactor.delete-request-store=filesystem` set it with no file (retention refuses to start without a delete-request store, `config.go:107-109`); the compactor works in `/data/loki/compactor` (`pkg/loki/config_wrapper.go:495-496`); deletion runs every 10 min, 2 h after marking (`config.go:51-53`).
- The image's collector receives logs by OTLP only (`otelcol-config.yaml`, `logs: receivers: [otlp]`); nothing reads Docker's files. An application can already export to `grafana-lgtm:4317/4318` (0007 AC-03); docs/migration.md doesn't say how.
- Other signals: Prometheus 3.14 starts without a retention flag (`run-prometheus.sh`), its default 15 days; Tempo 3.0.3's `block_retention` defaults to 14 days (tempo `tempodb/config.go:145`), which `grafana-lgtm/tempo-config.yaml` doesn't set; Pyroscope 2.3.0's: not checked.
- Docker: `daemon.json`'s `log-driver`/`log-opts` (string values) apply to containers created after the daemon's restart, existing ones keep theirs, and a container's own `logging` wins (Docker docs). The restart stops every container (no `live-restore`); those without `restart:` stay down.
- The demo host isn't set up yet (docs/demo-setup.md:3): no container to migrate today. The stand-in host runs `dockerd` without systemd (`tests/stand-in-host/entrypoint.sh:15`).

### Behaviour per persona

- **Application**: changes nothing; `logging` stays refused; its containers' output is a short buffer; for history, it exports its logs to Grafana LGTM (PA-03), kept PA-04's time.
- **Demo operator**: `docker logs` shows the recent lines, Grafana the retention's; on a running host, nothing to do (PA-01 C), or re-run `vps-bootstrap.sh` and accept a Docker restart (PA-01 A).
- **Developer**: Loki's retention in dev too (PA-04); nothing else.

### API and contracts

- Application's compose file: `logging` refused, `c4-app: refused: service <s>: logging: the demo host bounds every container's logs (README, "Accounts")`; under PA-01 B, accepted with PA-02's driver and values up to the bound, refused beyond.
- Each application container: `HostConfig.LogConfig` = PA-02's driver and bound (`docker inspect`).
- Loki: what arrives by OTLP is queryable for PA-04's retention, deleted within about 2 h after it.

### User interface

None.

### Data

`grafana_data` (Loki, and Prometheus and Tempo under PA-04 Y); the containers' log files under Docker's root.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| 0002: no `docker` group, one root-owned command | no account, group or sudo rule added (RQ-08) |
| 0007: the allowlist refuses what leaves the isolation | `logging` stays out of the application's hands (RQ-02); no Docker files mounted (RQ-08), unless PA-03 B |
| 0007 PA-02 C: Grafana LGTM attached as it is | unchanged; the retention shortens how long what is exposed stays |
| 0011's accepted risk: a hostile compose file | the bound holds against it: the application's file can't change it (PA-01 A or C) |
| README: one compose base, dev and demo alike | Loki's retention and the stack's bound in `compose.yml` (PA-04, PA-05) |

## Points of attention

### PA-01: Where the bound is set

- Issue: the intent's first open question.
- Options: A the daemon's default: `vps-bootstrap.sh` writes `daemon.json` and restarts Docker; bounds every container created afterwards, any account's; on a running host, the operator re-runs it, every container stops, and existing ones stay unbounded until recreated (RQ-03 then needs `c4-app` to force it); no systemd in the stand-in / B allowed per service: `c4-app` accepts a bounded `logging`; a service without one is still unbounded, so B alone fails RQ-01 / C imposed by `c4-app`: `logging` stays refused and `c4-app` sets the bound on every service of the model it runs; reaches a host with the stack's next deployment (`demo/deploy.sh:14-17` installs `c4-app`), recreates the containers at the next `up` (to measure: compose's config hash), no Docker restart, provable on the stand-in; covers only what `c4-app` starts, the only way an application starts anything / D A and C
- Recommendation: C: enforced at the one gate an application goes through, no restart of the host's Docker, RQ-03 met; A would add only what `c4-infra` starts by hand, which RQ-05 covers.
- Decides: tech lead
- Decision: C, as recommended (tech lead, Jérôme Wacongne, 2026-10-28)

### PA-02: The bound's driver and size

- Issue: the size is per container: an application with five containers keeps five times it.
- Options: A `json-file`, 10m × 3 (30 MB), the stack's own / B `local`, Docker's defaults 20m × 5, compressed (100 MB) / C `local`, 10m × 3, compressed
- Recommendation: A: one value on the host, the stack's; files a collector can read if PA-03 B ever comes; `docker logs` reads both drivers.
- Decides: PO
- Decision: A, as recommended (PO, Jérôme Wacongne, 2026-10-28)

### PA-03: The applications' logs in Loki

- Issue: the intent's second open question. Loki answers every application's network without authentication (0007 PA-02 C).
- Options: A each application exports its logs by OTLP to `grafana-lgtm` on its network, as it chooses; docs/migration.md says how; the stack reads no Docker file / B the collector reads every container's Docker files (`/var/lib/docker/containers` mounted into `grafana-lgtm`, `json-file` required): every container's output in Loki, the stack's and the databases' included, readable from every application's network: against RQ-08 and the intent's constraint / C neither: today, undocumented
- Recommendation: A: each application keeps choosing what it puts where every other can read; B widens 0007's accepted exposure to everything every container prints.
- Decides: PO (B: tech lead too)
- Decision: A, as recommended (PO, Jérôme Wacongne, 2026-10-28)

### PA-04: Loki's retention, and the other signals'

- Issue: the intent asks for Loki's; Tempo and Prometheus are bounded today by defaults an image upgrade may change; Pyroscope's is unknown.
- Options: value: A 7 days (the Keycloak dumps' rotation) / B 14 days (Tempo's default) / C 30 days. Scope: X logs only, the others recorded at their defaults / Y the same value pinned for logs, traces and metrics (Pyroscope's if the plan finds a setting). Where: the compose base, dev too / the demo override only
- Recommendation: B, Y, the compose base: a request's logs and traces expire together, a pinned value survives an upgrade, dev behaves as the demo.
- Decides: PO
- Decision: B, Y, the compose base, as recommended (PO, Jérôme Wacongne, 2026-10-28)

### PA-05: The stack's own services

- Issue: `default-logging` bounds them in both environments; under PA-01 A the daemon would too, on the demo host only.
- Options: A keep `default-logging`, aligned on PA-02's value / B drop it on the demo host, the daemon's default applying (PA-01 A or D only; dev keeps it)
- Recommendation: A: `compose.yml` stays self-sufficient, the workstation's Docker Desktop is never configured by the stack.
- Decides: tech lead
- Decision: A, as recommended (tech lead, Jérôme Wacongne, 2026-10-28)

## Acceptance criteria

- **AC-01:** Given an application on the stand-in host whose compose file sets no `logging`, when `sudo c4-app up` runs, then each container's `HostConfig.LogConfig` is PA-02's, and a container printing beyond the bound keeps no more than it on disk. (RQ-01)
- **AC-02:** Given a service with `logging` (`driver: json-file` without options, `driver: none`, another driver), when `sudo c4-app up` and `pull` run, then each is refused with RQ-02's message and nothing starts (PA-01 B: the bounded form is accepted). (RQ-02)
- **AC-03:** Given an application's containers started unbounded, when the stack deploys and the application runs `sudo c4-app up` with the same files, then they run again with the bound. (RQ-03)
- **AC-04:** Given a running application container, then `docker logs` and `docker compose -p <app> logs`, run as `c4-infra`, show its last lines. (RQ-04)
- **AC-05:** Given the stack in dev and on the stand-in, then each of its containers' `LogConfig` is PA-05's. (RQ-05)
- **AC-06:** Given `grafana-lgtm`, then Loki's `/config` shows retention enabled with PA-04's period, a log posted by OTLP is read back (`tests/0007-lgtm.sh` passes), and so after a restart. (RQ-06)
- **AC-07:** Given PA-04 Y, then Prometheus's flags and Tempo's configuration show the same retention. (RQ-07)
- **AC-08:** Given the stand-in host after the change, then each application's account is outside `docker` with `sudo c4-app` as its only rule, and no container mounts Docker's directories (PA-03 A). (RQ-08)
- **AC-09:** Given the README and docs/migration.md, then they state the bound, the refusal of `logging`, the retention and how to export logs. (RQ-09)

## Intent questions

- The bound by the host's daemon, or allowed per service? → PA-01 (and C, imposed by `c4-app`); its size → PA-02.
- Do the applications' logs go to Loki, and how? → PA-03; Loki's retention → PA-04.

## Change log

- v1 — 2026-10-28 — first version
- v1 — 2026-10-28 — approved: every point of attention decided as recommended (Jérôme Wacongne, PO and tech lead)
