# Intent: c4-app's isolation leaves residual paths between an application's account and the host or other applications

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: bug
- Source: conversation (sdlc-verify round 2 review, 2026-10-23)
- Spec needed: yes
- Status: proposed
- Opened: 2026-10-23
- Decided: —
- Supersedes: —

## Problem

On the demo host, an application's account deploys through `sudo c4-app` (0002), whose model check and staging keep its containers inside its isolation (0007). The fresh review of 0002, 0003 and 0007's two fix rounds (`40c97ee..8c318d9`) found the paths below, which may still lead from one application's account or containers to the host, the shared stack or another application. **Each was found by reading the code; none was measured** (no reproduction on the stand-in host). Lines are those of `8c318d9`; the numbers are the review's (11 and 12, two regressions, were fixed in round 3). On 2026-10-23 the product owner and tech lead accepted the residual risk and limited round 3 to those regressions (0007's plan, *Deviations*).

`demo/c4-app`'s model check (allowlist) and staging:

1. `env_file` is allowlisted with no path check (`demo/c4-app:191`): a model that still names one when root's compose runs it would have root read that file (the shared stack's `.env`) into a container.
2. `read_model` runs `docker compose config` as the application with `HOME=/home/<app>` (`:170`): its `~/.docker/config.json` and `~/.docker/cli-plugins` (a `docker-compose` plugin of its own) choose the model's text, so what the check assumes compose normalised (absolute paths, `env_file` merged, interpolation) may not hold.
3. `build.cache_from` takes any value (`:201`): `type=local,src=<host path>` would have root's build import a cache from anywhere on the host.
4. The `remote` exemption of build contexts (`:187`, `:275`) lets `docker-image://`, `https://`, `git://`, `git@` and `service:` through in `additional_contexts`: `docker-image://<another application's image>` copies its files into this application's image.
5. Any `image:` without `build`, and a Dockerfile's `FROM` or `COPY --from`, can run or read another application's image in the one Docker daemon (`:190`). Whether a built `<app>-<service>:latest` can be shadowed by a pull of `docker.io/library/<app>-<service>` wasn't checked.
6. The top-level `networks` and `volumes` keys aren't allowlisted (`:208-222`): `ipam` subnets (the host's or a shared network's range), `internal`, `enable_ipv6`, `attachable`, `labels`.
7. Only `type: bind` volume entries are checked (`:254`): `volume` with options, `tmpfs`, `npipe`, `cluster`, `image` (another application's image mounted as files), and the bind sub-keys `propagation`, `create_host_path`, pass.
8. `.run.<app>` shares one namespace with `.<app>.lock` and `.<app>.incoming` (`:119`, `:126`, `:134`): an application named `lock` takes `.run.lock`, the lock file of an application named `run`, as its snapshot (removed, then recreated as a directory); `incoming` likewise takes `run`'s incoming copy.
9. Aliases and `container_name` only need the `<app>.` prefix (`:241`): when `INFRA_HOST` starts with `<app>.` (an application `infra` with `infra.c4-soft.com`), that application's container takes the shared host's name on its network, where the shared services are attached.
10. A `secrets` or `configs` `file:` may be the staging root itself, `file: .` (`:224`), which round 1 refused for bind mounts.
13. `down` requires the current `compose.yml` to pass the allowlist (`:410`): a project started under the former denylist, or whose new push was refused, can't be stopped by its account.
18. Adding `$host` to `reserved` (`:189`) does nothing: dotted service names are refused anyway.

The shared stack's scripts:

14. `up.sh:71`: every `caddy reload` failure, a failed `docker exec` or an admin endpoint not ready yet included, says the reverse proxy "refuses its configuration".
15. `networks.sh:66`: the early-return path writes `compose.apps.yml` with a plain `>`, outside the `flock` and the `mktemp` + `mv`.
16. `registry.sh:71`, `dotenv_value`: a read error is folded into `|| true`, so an unreadable `.env` reads as missing keys (`INFRA_HOST` empty: `networks.sh ensure` attaches the reverse proxy without the shared host's alias).
17. `registry.sh:91`: an unquoted value ends at ` #` only, while compose ends it at any whitespace before `#` (a tab): the scripts and the containers would read two different values.

Open risks of the round-2 fix:

- the one daemon lets each application read the others' images (see 5);
- `c4-app pull` of a model naming another application's image reference refreshes that tag, which the other application's next `up` runs.

## Proposed outcome

A measured verdict on each path above: reproduced on the stand-in host, or shown not to hold, with the measurement recorded. The paths that hold are closed, each proven by a test on the stand-in host that fails before the fix. Success criterion: no path of this list is left without a measurement and, when it holds, a passing test.

## Affected users and systems

- Demo visitor (every application's accounts and data on the demo host), Application, Demo operator; Developer for 14.
- Demo stack (`demo/`: `c4-app`), registration (`register-app.sh`), the dev stack (`up.sh`); `registry.sh` and `networks.sh`, *not declared in the project context* (they hold the registry's and the networks' rules since 0004 and 0007).

## Constraints

- High-risk under the project's risk rules: the isolation between applications, and what a host exposes.
- One small VPS and one Docker daemon, no orchestrator (0002, 0007); 0002 (accounts outside the `docker` group, one root-owned command) and 0007 (one network per application) hold.
- The demo host is deployed (`origin/main` at `08dfa3d`): a fix reaches it through the deployment workflow.

## Open questions

- Which of these paths hold, once measured on the stand-in host? — the spec (tech lead).
- Suggested solution: reduce the surface — no build on the demo host, images only from the application's own GHCR namespace, a minimal set of keys. — the spec decides.
- Suggested solution: a model written by root from a declarative file of the application's, rather than its own compose file checked. — the spec decides.
- Suggested solution: a rootless Docker daemon per application. — the spec decides.
- Does any application need to build its images on the demo host, or to run an image outside its own GHCR namespace? — PO.
- Does the acceptance of 2026-10-23 still hold once a second application deploys to the demo host (most paths need two)? — PO.
