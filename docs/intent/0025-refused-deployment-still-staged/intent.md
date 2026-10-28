# Intent: A refused `sudo c4-app up` or `pull` still copies the refused files where the application's running containers read them

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: bug
- Source: conversation (0011's verifier, 2026-10-28; opened by the product owner the same day)
- Spec needed: no
- Status: planned
- Opened: 2026-10-28
- Decided: 2026-10-28
- Supersedes: —
- Mode: bootstrap

## Problem

`sudo c4-app up` (and `pull`) copies the application's `~/<app>/<app>/` into `/var/lib/c4-apps/<app>/` (`stage()`, an `rsync --delete`) before it reads and checks the compose model (`read_model`, `check_model`). That directory is what the application's running containers mount. A deployment the check refuses has therefore already replaced, or removed, the files they read: "nothing was started or changed" (0011's RQ-01, the refusal's own message) holds for the containers, not for their files.

- Steps: on the demo host, an application runs, its containers mounting files of `/var/lib/c4-apps/<app>/` (read-only bind mounts); its workflow sends a new `~/<app>/<app>/` whose `compose.yml` the check refuses (a published port, a service that builds…) along with a changed mounted file; `sudo c4-app up`.
- Expected: refused, and the running application unchanged: its containers read the files they read before.
- Observed (read in `demo/c4-app` at `main` fc47b85, not reproduced): refused, nothing started, but `/var/lib/c4-apps/<app>/` holds the new files, the running containers read them, and the files the new copy no longer has are gone.
- Environment: the demo host, `demo/c4-app`.

A refused deployment is half applied: the application runs its old containers on its new files, until a deployment passes the check.

## Proposed outcome

A deployment `c4-app` refuses leaves `/var/lib/c4-apps/<app>/` as it was: the running containers keep reading the same files, and the refusal says so as today.

## Affected users and systems

- Personas: Application (its deployment on the demo host); Demo operator (reads a refused deployment)
- Modules / systems: demo host (`demo/c4-app`)

## Constraints

- What 0002 and 0007 hold stays: the copy is read as the application, a link or a special file is refused before anything, root's compose runs the root-only snapshot of the model it checked.
- `down` reads no file (0011): out of this change.

## Open questions

- Suggested solution: check a copy made beside the staging directory, and put it in place only once the check passes — the plan.
- Whether `register`, which stages too, has the same gap (its refusals come from `register-app.sh`, after the copy) — the plan.
