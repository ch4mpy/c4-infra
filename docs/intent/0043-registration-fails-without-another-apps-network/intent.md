# Intent: An application's registration fails while another registered application's network is gone

- Author: Jérôme Wacongne (product owner, tech lead); drafted by the agent from 0034's observation of 2026-10-28
- Kind: bug
- Source: conversation (0034's plan, *Deviations*, 2026-10-28: "Observed meanwhile, outside this intent")
- Spec needed: no
- Status: planned
- Opened: 2026-10-30
- Decided: 2026-10-30
- Supersedes: —
- Mode: bootstrap

## Problem

On 2026-10-28, with `c4-infra.faito` removed by `bash networks.sh remove faito`, `bash register-app.sh --app tickee` failed: `could not find a network matching network mode c4-infra.faito`. The shared services stay broken that way until compose recreates them: an application's network removed by hand, or by a test's cleanup, stops the other applications' registrations, and a restart of Keycloak (a theme's installation on the demo host) fails the same way.

Observed (2026-10-30):

- On the dev stack, the five shared services' primary network is an application's: `docker inspect -f '{{.HostConfig.NetworkMode}}'` gives `c4-infra.faito` for `keycloak`, `reverse-proxy`, `mailpit`, `rabbitmq` and `grafana-lgtm`.
- Reproduced on a throwaway compose project (Compose v5.6.1, Docker 29.9.2): a service on its own network `default` and on an external network whose key sorts before it (`c4-0043.app`) is created with that network as its `NetworkMode`; once that network is removed, `docker restart` fails with `could not find a network matching network mode c4-0043.app`. With `priority: 100` on `default`, the container's `NetworkMode` is its own network, and it restarts after the removal.

Steps: the dev stack up with Faito registered; `bash networks.sh remove faito`; `docker restart c4-infra.keycloak`. Expected: Keycloak restarts. Observed: the error above.

## Proposed outcome

The shared services' primary network is the stack's own, `c4-infra`, which no application removes: removing an application's network leaves the shared services able to restart, and the other applications able to register.

Success criterion: on the dev stack and in the demo's compose model, each of the five shared services' primary network is `c4-infra`, whatever the applications' networks are named.

## Affected users and systems

- Developer, Demo operator, Application (the registrations).
- `compose.yml` (the shared services' networks), `networks.sh`.

## Constraints

- 0007: the shared services join each application's network, kept in `compose.apps.yml`.
- The fix recreates the five shared services once, at the next `up.sh` in dev and the next deployment of the stack on the demo host (their compose model changes).
