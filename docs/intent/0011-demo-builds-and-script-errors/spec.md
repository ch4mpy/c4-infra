# Spec: The demo host builds images the applications' CI already builds, and some stack scripts misreport errors

- Intent: [0011](intent.md)
- Status: approved
- Version: 1
- Risk: high (rule: what the demo host runs as root, `sudo c4-app`; tech lead's agreement required)
- Policies applied: none yet; standing constraints: README design and "Accounts", 0002 (accounts outside the `docker` group, one root-owned command), 0007 (one network per application, the allowlist), 0011's accepted risk (a leaked deployment key)
- Approved: v1 2026-10-23, Jérôme Wacongne (PO, and tech lead for the high risk)

## Summary

`sudo c4-app` refuses a compose file that builds an image: the demo host runs only images an application's CI pushed to a registry, and the checks that made building safe there go. The stack's scripts stop misreporting their errors: `c4-app down` stops a project whatever its current compose file, `up.sh` tells a refused configuration from a proxy it can't reach and runs on a fresh clone, `networks.sh` writes its file atomically under its lock, `registry.sh` tells an unreadable `.env` from a missing key, `routes.sh` refuses an empty option key with its usual message. Each fix is proven by a test that fails before it.

## Requirements

- REQ-1 `sudo c4-app up`, `pull` and `down` refuse a compose model in which a service has `build`, naming the service and saying that the application's CI builds its images and pushes them to a registry; nothing is started or changed. (intent: outcome, criterion)
- REQ-2 The checks that only building needed go, with their documentation: the `build` sub-key allowlist, the confinement of `context`, `dockerfile` and `additional_contexts`, the refusal of `image` beside `build`, and of a `-` in a building service's name. (intent: outcome)
- REQ-3 The applications' fixtures, which pull their images, still deploy on the stand-in host. (intent: criterion)
- REQ-4 `sudo c4-app down` stops and removes the application's containers and networks (its compose project) even when the `compose.yml` it holds now is refused, running nothing a model declares (hooks, providers); its volumes stay. (intent: defect 1)
- REQ-5 `up.sh` tells, when the proxy's reload fails, a configuration Caddy refuses (its message, then "fix caddy/…") from a proxy it can't reach (container not running, `docker exec` failing, admin endpoint not ready: "the reverse proxy isn't reachable, retry"). (intent: defect 2)
- REQ-6 `networks.sh` writes `compose.apps.yml` the same way on every path, its early return included: under its lock, through a temporary file renamed into place. (intent: defect 3)
- REQ-7 `registry.sh` tells an `.env` it can't read (an error naming the file) from a key that is missing. (intent: defect 4)
- REQ-8 (PA-2 A: no fix, `registry.sh` unchanged) `registry.sh` and compose read an unquoted value with a comment the same way, guarded by a test. (intent: defect 5)
- REQ-9 `c4-app`'s check no longer reads `INFRA_HOST` to refuse a service named after it, which can't happen (a service name has no dot); the header and the README stop listing it. (intent: defect 6)
- REQ-10 `up.sh` runs on a fresh clone, without `certs/tls.crt`, as on a workstation that has one. (intent: defect 7)
- REQ-11 `routes.sh` refuses an option with an empty key (`=x`) as `<file>:<line>: …`, like any unknown option, and registers nothing. (intent: defect 8)
- REQ-12 Each fix of REQ-4 to REQ-7 and REQ-9 to REQ-11 is proven by a test that fails on the code before it. (intent: outcome)

## Out of scope

- Everything 0011's accepted risk lists (a hostile compose file from a leaked deployment key): `env_file`, `docker compose config`'s `HOME`, top-level networks and volumes beyond the allowlist, `secrets`/`configs` `file: .`, the staging namespace, aliases, another application's image through `image:` or `pull` (PA-1 A: not restricted).
- c4-infra's own images (Keycloak, and the proxy of 0013): its workflow builds them and the demo host pulls them already.
- Building in dev: an application's dev compose files are its own.

## Design

### Current behaviour

On `origin/main` (`0697208`):

- `demo/c4-app:263-281`: a service with `build` is checked (`build_allowed`, `:200-201`: `context`, `dockerfile`, `additional_contexts`, `args`, `target`, `labels`, `cache_from`, `no_cache`, `pull`, `platforms`; `remote`, `:187`, lets `docker-image://` and other remote contexts through; `cache_from` unchecked). Deployments never build: the migration guide's workflows push to GHCR and run `sudo c4-app pull`; the only fixtures that build are 0007's hostile ones (`tests/fixtures/0007/hostile/build-*.yml`, asserted by `tests/0007-compose-check.stand-in.sh`).
- Defect 1, `demo/c4-app:405-412`: `down` runs `check_model` before `compose down`.
- Defect 2, `up.sh:92-94`: any `caddy reload` failure says "The reverse proxy refuses its configuration".
- Defect 3, `networks.sh:64-66`: with no daemon answering, `printf … > "$APPS_FILE"`, before the `flock` (`:74-76`) and outside `mktemp` + `mv` (`:80-110`).
- Defect 4, `registry.sh:74-75`: `grep … "$file" | tail -n 1) || true`: a read error reads as a missing key.
- Defect 5, `registry.sh:95` ends an unquoted value at ` #`. **Not reproduced** with Docker Compose v5.6.0 (Docker 29.8.2): for `A=x # c`, `B=x<tab># c`, `C=x#c`, `D=x  #c`, `E=x<tab>#c`, `F=x #`, compose reads `x`, `x<tab># c`, `x#c`, `x`, `x<tab>#c`, `x`, and `dotenv_value` the same six values: a tab doesn't start a comment.
- Defect 6, `demo/c4-app:188-189`: `reserved` adds `$host`; `:230` refuses any service name outside `^[a-z0-9][a-z0-9_-]*$`, and `INFRA_HOST` is a dotted name.
- Defect 7, `up.sh:55`: `certificate_before=$(cat certs/tls.crt 2> /dev/null | cksum)` under `set -euo pipefail`; the same line with a missing file exits 1 with no message (measured).
- Defect 8, `routes.sh:138-140`: `bash routes.sh generate <file> faito dev` on `/x/* gateway =x` prints `routes.sh: line 140: seen_options: bad array subscript`, exit 1 (measured).

### Behaviour per persona

- Application: a workflow that pulls its images deploys as before; a compose file that builds is refused at `up`, `pull` or `down`, with the reason. Its account can always stop its project.
- Developer: `up.sh` works on a fresh clone, and says whether to fix the proxy's configuration or retry.
- Demo operator: nothing new to do.

### API and contracts

- `sudo c4-app up|pull|down`: a new refusal, `service <s>: build: the demo host runs the images the application's CI pushes to a registry (README.md, "Accounts")`; the build-specific refusals go.
- `up.sh`, `routes.sh`, `registry.sh`, `networks.sh`: same options and exit codes; only the messages of REQ-5, REQ-7 and REQ-11 change.

### User interface

None.

### Data

None.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| 0002: one root-owned command, accounts outside the `docker` group | unchanged; `down` stays within the application's own compose project (REQ-4) |
| 0007: the allowlist, nothing unchecked reaches root's compose | REQ-1 shrinks the allowlist; REQ-4's `down` hands compose no model |
| 0011's accepted risk | unchanged (PA-1 A) |
| README "Accounts" | REQ-2, REQ-9 update it |

## Points of attention

### PA-1 Each application's images in its own registry namespace

- Issue: the intent's open question. With building gone, an application's `image:` may still name another application's image (0011's accepted risk); a namespace per application, declared in `registry.txt`, would refuse it.
- Options: A no restriction: under the accepted risk it would only guard against a mistake / B a registry column with each application's image prefix (for example `ghcr.io/ch4mpy/turu-`), refused otherwise by `c4-app`; the registry's format changes (0004)
- Recommendation: A: a mistaken image name fails visibly at deployment, and B changes the registry's format for every application.
- Decides: product owner
- Decision: A, no restriction (Jérôme Wacongne, product owner, 2026-10-23)

### PA-2 Defect 5 is not reproduced

- Issue: with Docker Compose v5.6.0, a tab before `#` doesn't start a comment, and `registry.sh` reads all six cases as compose does. The intent asks for eight defects fixed.
- Options: A drop the fix; keep a test asserting that `dotenv_value` and compose read these cases alike, run on the stand-in host's compose too (the demo host's version) / B end a value at any whitespace before `#` anyway (then it would differ from compose)
- Recommendation: A: the test guards against a compose change, without a change that would create the divergence.
- Decides: product owner
- Decision: A, no fix; a test asserts the equivalence (Jérôme Wacongne, product owner, 2026-10-23); departs knowingly from the intent's "eight defects fixed": defect 5 doesn't exist with the demo host's compose

## Acceptance criteria

- AC-1 Given the stand-in host and an application whose compose file has a service with `build`, when it runs `sudo c4-app up` (and `pull`, `down`), then refused naming the service and the reason, nothing started. (REQ-1)
- AC-2 Given 0007's hostile build fixtures, when checked, then each is refused by REQ-1's message. (REQ-1, REQ-2)
- AC-3 Given the applications' fixtures (Faito, Hurura'a), when deployed on the stand-in host, then they start as before. (REQ-3)
- AC-4 Given a project started on the stand-in host, then its `compose.yml` replaced by a refused one, when its account runs `sudo c4-app down`, then its containers and networks are gone, its volumes kept, and no hook of the new file ran. (REQ-4)
- AC-5 Given `up.sh` with the proxy's container stopped, then its message says the proxy isn't reachable; with a site Caddy refuses, then it says the configuration is refused. (REQ-5)
- AC-6 Given no daemon answering and no `compose.apps.yml`, when `networks.sh` writes it while another rewrite holds the lock, then it waits for the lock and the file is never partial. (REQ-6)
- AC-7 Given an `.env` that exists but can't be read, when `registry.sh` reads a key, then it fails naming the file. (REQ-7)
- AC-8 Given the six values of Current behaviour, when read by `dotenv_value` and by `docker compose config`, then alike, in dev and on the stand-in host. (REQ-8, PA-2 A)
- AC-9 Given a service named like `INFRA_HOST`, then refused by the name rule, and the check reads no `INFRA_HOST`. (REQ-9)
- AC-10 Given a clone without `certs/tls.crt`, when `up.sh` runs, then it creates the certificate and starts the stack, or stops with a message: never a silent exit. (REQ-10)
- AC-11 Given a routes file with `/x/* gateway =x`, when registered, then refused as `<file>:1: …`, nothing registered. (REQ-11)
- AC-12 Given the tests of AC-4 to AC-7 and AC-9 to AC-11, run on the code before the fix, then each fails. (REQ-12)

## Intent questions

- Restrict each application's images to its own registry namespace, declared in `registry.txt`? → PA-1, decided A: no restriction.

## Change log

- v1 — 2026-10-23 — first version
- v1 — 2026-10-23 — approved: PA-1 A, PA-2 A (REQ-8 reworded as a guard, REQ-12 no longer covers it); tech lead's agreement for the high risk (Jérôme Wacongne, PO and tech lead)
