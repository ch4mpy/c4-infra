# Intent: The demo host builds images the applications' CI already builds, and some stack scripts misreport errors

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: bug
- Source: conversation (sdlc-verify round 2 review of 0002, 0003 and 0007, 2026-10-23; need clarified by the product owner the same day)
- Spec needed: yes
- Status: proposed
- Opened: 2026-10-23
- Decided: —
- Supersedes: —

## Problem

Every application deployed on the demo host is assembled by a GitHub or GitLab workflow the product owner approves, from a repository he trusts with secrets and keys. Yet:

- `sudo c4-app` still lets an application's compose file build images on the demo host (`build:`), and keeps the checks that make building safe there: `context`, `dockerfile` and `additional_contexts` confined to the staging tree; `build.network`, `privileged`, `entitlements`, `ssh` and `tags` refused; no `image:` beside `build:`; no `-` in a building service's name (`demo/c4-app`, review rounds 1 and 2). Deployments never use this surface, and the review still found it incomplete: `build.cache_from` is unchecked, and `docker-image://` and the other remote contexts get through.
- Some scripts of the shared stack misreport or mishandle errors:
  1. `demo/c4-app:410`: `down` requires the current `compose.yml` to pass the allowlist, so a project started under the former denylist, or whose new push was refused, can't be stopped by its account.
  2. `up.sh:71`: every `caddy reload` failure, a failed `docker exec` or an admin endpoint not ready yet included, says the reverse proxy "refuses its configuration".
  3. `networks.sh:66`: the early-return path writes `compose.apps.yml` with a plain `>`, outside the `flock` and the `mktemp` + `mv`.
  4. `registry.sh:71` (`dotenv_value`): a read error is folded into `|| true`, so an unreadable `.env` reads as missing keys (`INFRA_HOST` empty: the reverse proxy loses the shared host's alias).
  5. `registry.sh:91`: an unquoted value ends at ` #` only, while compose ends it at any whitespace before `#`: the scripts and the containers read two different values.
  6. `demo/c4-app:189`: `$host` in `reserved` is dead code, since dotted service names are refused anyway.

## Proposed outcome

- The demo host runs only images pulled from a registry: `sudo c4-app` refuses a compose file that builds, saying the application's CI builds its images, and the build checks go. Success criterion: on the stand-in host, a compose file with `build:` is refused, and the applications' fixtures still deploy.
- The six script defects above are fixed, each proven by a test that fails before the fix.

## Affected users and systems

- Application (its deployment workflow), Demo operator; Developer for 2 and 3.
- Demo stack (`demo/c4-app`), dev stack (`up.sh`); `registry.sh` and `networks.sh`, *not declared in the project context* (they hold the registry's and the networks' rules since 0004 and 0007).

## Constraints

- High-risk under the project's risk rules: what the demo host runs as root.
- **Accepted risk, out of scope** (product owner, 2026-10-23): a leaked deployment key of an application (its repository's or its CI's secrets) is not contained. The review's paths that need one stay open, recorded here and in the 0007 plan: `env_file` without a path check; `docker compose config` run with the application's `HOME` (`~/.docker/cli-plugins`); top-level `networks` and `volumes`, and volume types other than `bind`, outside the allowlist; a `secrets` or `configs` `file: .`; the `.run.<app>`, `.<app>.lock`, `.<app>.incoming` namespace; aliases when `INFRA_HOST` starts with `<app>.`; another application's image run or read through `image:`, a Dockerfile's `FROM`, or `pull`, in the one daemon. A running container gains none of them: each needs a hostile compose file.
- One small VPS and one Docker daemon, no orchestrator; 0002 (accounts outside the `docker` group, one root-owned command) and 0007 (one network per application) hold.
- The demo host is deployed (`origin/main` at `08dfa3d`): a fix reaches it through the deployment workflow.

## Open questions

- Restrict each application's images to its own registry namespace, declared in `registry.txt`? Under the accepted risk it would only guard against a mistake. — product owner, at the spec.
