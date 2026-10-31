# Intent: The first deployment of the stack after an application's first registration recreates the shared services

- Author: Jérôme Wacongne (product owner, tech lead); drafted by the agent from the demo host's deployments of 2026-10-30
- Kind: change
- Source: conversation (2026-10-30: the handover's open question on run 41094847195, read again with Tickee's first deployment)
- Spec needed: no
- Status: delivered (2026-10-30)
- Opened: 2026-10-30
- Decided: 2026-10-30
- Supersedes: —
- Mode: bootstrap

## Problem

The deployment of the stack of 2026-10-30 16:59 UTC (run 41094847195) recreated five containers of the demo host (`grafana-lgtm`, `keycloak`, `mailpit`, `rabbitmq`, `reverse-proxy`), though no deployed file, image tag or secret had changed; the one before (40808682088, 2026-10-29) and the one after (41116396675) recreated none. The handover left it as unexplained, to read on the VPS. An operator who sees the shared Keycloak and proxy restart for every application, with no change of the stack, can't tell a fault from a normal event.

Observed (2026-10-30):

- Between those deployments, Tickee registered on the demo host for the first time (its run 40994537547, deploy job 03:14:33 to 03:16:14 UTC): the first application `sudo c4-app` deployed.
- The five recreated are exactly the shared services `networks.sh` attaches to each application's network, `keycloak-db` aside. `networks.sh ensure` attaches them at the registration (`docker network connect`) and writes the new network into `compose.apps.yml`; `demo/deploy.sh:28` writes that file again, then `:53` runs `docker compose up`, whose model of the five now names a network their containers were created without.

## Proposed outcome

The behaviour is measured on a stand-in demo host and stated in the README: when it happens (the first deployment of the stack after an application's first registration), what it recreates, what it costs the other applications, and that it is expected. No change of behaviour.

Success criterion: on a stand-in, the deployment that follows a first registration recreates the five shared services and not `keycloak-db`, the next one recreates none, and the README says so.

## Affected users and systems

- Demo operator, Application (every application on the demo host, during that deployment).
- Demo stack (`demo/deploy.sh`, `networks.sh`, `compose.apps.yml`), README.

## Constraints

- 0007: each application's network holds the shared services, kept in `compose.apps.yml` so that the attachments survive the stack's recreation.

## Decided at acceptance (the product owner, 2026-10-30)

- Measure and document. Set aside: recreating the shared services at the registration itself (the cut during the application's own deployment), and keeping the applications' networks out of the compose model (reverses 0007's choice).
