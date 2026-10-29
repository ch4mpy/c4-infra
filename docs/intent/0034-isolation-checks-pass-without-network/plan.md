# Plan: tests/0007-dev.sh's isolation checks pass when the application's network doesn't exist

- Spec: [v1](spec.md) (approved 2026-10-28: PA-01 B, PA-02 A)
- Status: approved
- Branch: 0034-isolation-checks-pass-without-network
- Approved: 2026-10-28, Jérôme Wacongne (engineer; the batch and the agent, product owner)

## Starting point

Read on 2026-10-28, `main` at de2be13. The branch is at 53cbfb7: the intent, spec v1, and `main` merged at 510e54e. Nothing was measured for this draft (plan mode, no Docker); step 0 measures.

- **`tests/0007-dev.sh`**:
  - `fails` (`:94-100`) passes whenever its command exits non-zero, and discards the output. Its comment, "(a refused connection)", is the assumption the intent disproves.
  - Part `tickee` (`:157-188`):
    - `:178-179`, the control: `docker run --rm --network c4-infra.tickee alpine:3 nc -z -w 3 "$STANDIN" 7080`, under `check`. A missing image or a daemon error KOs it.
    - `:180-181` (by name) and `:184-185` (by address): the same probe on `c4-infra.faito`, under `fails`. A missing `c4-infra.faito`, image or daemon passes them. Nothing in the part checks that `c4-infra.faito` exists. It does create Tickee's network when it's missing, and removes it at the end (`:159`, `:47`).
    - `:182`: `{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}` glues together the addresses of a container on two networks. nc can only take the result for a name it can't resolve, so under `fails` the by-address check would pass.
    - `:187`: `test -z "$(docker ps -aq -f "name=^$STANDIN\$")"`. A failed `docker ps` reads as "removed".
  - Part `guard`, `:211-213`: `docker compose config --format json | jq '….networks["c4-infra.faito"].aliases // [] …'`, then `fails in_list host.docker.internal "$found"`. A failed `docker compose config` gives an empty list, which passes. So does a model whose reverse proxy isn't on `c4-infra.faito`. In dev, the reverse proxy joins each application's network without an alias (`networks.sh:84-90`; `INFRA_HOST=host.docker.internal`, `env.sh:32`).
  - `check` (`tests/lib/assert.sh:18-28`) prints its command's output, indented by five spaces, under a KO.
  - A full run registers Faito first (part `networks`, `:140-141`). `bash tests/0007-dev.sh tickee` alone doesn't.
  - The whole test takes 67 s (`.git/c4-infra-test-durations`).
- **The evidence**:
  - 0023's verification, "Pre-existing findings" (`docs/intent/0023-ldap-leaves-the-stack/plan.md:75`).
  - Its mutation, the stand-in on `c4-infra.faito` instead of Tickee's network: the control and both negative checks KO (`:69`).
- **Precedents**:
  - `tests/0007-isolation.stand-in.sh`:
    - a missing probe image stops the test with a KO (`:195-199`);
    - a container's addresses are listed one per line (`addresses_of`, `:111-114`), with one check per address (`:237-241`).
  - `tests/0018-registry-grows.sh` runs `tests/0004-registry.sh` in a scratch copy and declares it (`# covers: … tests/0004-registry.sh …`). 0018 froze it while `tests/0004-registry.sh` was being fixed (0018's plan, step 1).
  - `tests/lib/argv-log.sh:22-34`: a wrapper put first on `PATH` that execs the real command, found with `command -v` before `PATH` changes.
- **The selection**:
  - No test declares `tests/0007-dev.sh` except itself.
  - `tests/0019-collation.sh` declares `tests/` (`:9`).
  - `docs/intent/` concerns no test (`tests/run.sh:98-121`).
  - There are 72 tests today.
- **Faito in dev**:
  - `../faito/deploy-dev.sh` registers Faito, its network included, and starts its database from `compose-rest-api-db.yml`, which is on none of the stack's networks.
  - Its gateways run on the host (0023, spec v2).
  - `bash networks.sh remove faito` detaches the shared services and removes the network (`networks.sh:154-165`). `bash register-app.sh --app faito` creates it again (`:133-135`), as part `networks` does.
- **Other facts**:
  - `alpine:3` is the probe's image. `tests/lib/suite-lock.sh:14-16` runs it at every `tests/run.sh`, which pulls it when it's missing.
  - `.claude/frozen-tests.local` is ignored by git (`.gitignore`) and still lists `tests/0030-federation-ids.sh`, left from 0030 (delivered).
  - 0032 (specified, on `main`) and 0033 (specified, on its own branch) are in progress, so 0034 stays on its branch. The only file it shares with them is `docs/intent/README.md` (the index).

## Engineer's choices

- Decided by Jérôme Wacongne (engineer), 2026-10-28: every recommendation below.

Proposed by Claude, for Jérôme Wacongne (engineer) to confirm with this plan:

1. **The reproducing test, and how it stays frozen** *(to confirm)*.
   - **The tension**: the test being fixed is `tests/0007-dev.sh` itself. A check written first inside it can't be frozen, because step 2 changes that file.
   - **The proposal**: the reproduction is a new test, `tests/0034-negative-checks.sh` (`# covers: tests/0007-dev.sh`). It runs `tests/0007-dev.sh` from the working tree, in four variants, and asserts their verdicts. It is committed alone and frozen at step 1. Step 2 changes `tests/0007-dev.sh` only, which isn't frozen: it is the code under fix. This is 0018's pattern.
   - **How a variant runs** (`bash -c "<copy>" tests/0007-dev.sh <parts>`):
     - from the repository, with `$0` set to `tests/0007-dev.sh`, so that the copy's `cd "$(dirname "$0")/.."` lands in the repository;
     - **as a copy** when the test's own text must change: `c4-infra.faito` → `c4-infra.0034-no-such-app`, which also reaches the jq lookup of `:211`, and `alpine:3` → `alpine:0034-no-such-tag`. The spec's AC-02 and AC-04 ask for "a copy";
     - **as it is, with a `docker` wrapper first on `PATH`** when docker must behave otherwise: the stand-in also connected to `c4-infra.faito`, or `docker ps` and the dev model failing.
   - **What the frozen test asks of the fix**:
     - `c4-infra.faito` and `alpine:3` stay in the file as text, as a literal or a constant;
     - the labels stay as they are (RQ-05);
     - `:187` and `:211` keep their commands, `docker ps -aq -f name=^$STANDIN$` and `docker compose config --format json`.
   - **Rejected**:
     - (b) new checks inside `tests/0007-dev.sh`, frozen: the fix is in the same file;
     - (c) the probe as a helper in `tests/lib/`: out of scope (PA-01 D), and it would run every test;
     - (d) environment overrides in `tests/0007-dev.sh` (`FAITO_NETWORK`, `PROBE_IMAGE`): today's file ignores them, so the test couldn't reproduce the bug before the fix.
2. **How a negative check tells a failed connection from a probe that never ran** *(to confirm)*.
   - **The probe**: one `probe <network> <target>`, shared by the control and the negative checks: `MSYS_NO_PATHCONV=1 docker run --rm --network <network> alpine:3 sh -c 'nc -vv -z -w 3 "$1" 7080 2>&1; echo "nc exit $?"' sh <target>`. Docker's output is captured too (`2>&1`), with its status, and `\r` stripped.
   - **The verdict**:
     - no `nc exit` line: the container never ran on that network (network, image, daemon: RQ-02). KO `the probe didn't run on <network> (docker run exit <n>)`, with docker's message;
     - `nc exit 0`: KO `the connection succeeded`;
     - `nc exit 1` with a reason RQ-01 lists: passes. By name: the name unresolved, refused, or timed out. By address: refused or timed out. Each reason is nc's own words as step 0 measures them, one constant each;
     - anything else: KO with nc's output (`nc: not found` exits 127).
     - The control passes on `nc exit 0` only.
   - **Rejected**:
     - (A) docker run's exit status (125/126/127 for docker, 1 for nc): it rests on docker's codes, and a daemon error that exits 1 would pass;
     - (B) nc's status alone (1 passes): any other failure of nc that exits 1 would pass, such as the glued addresses of `:182`, read as a name, or a usage error.
3. **By address: each address of the stand-in** *(to confirm)*.
   - **The proposal**: the addresses are listed one per line (`{{range …}}{{.IPAddress}}{{"\n"}}{{end}}`, as `0007-isolation.stand-in.sh:111-114` does), with one check each under today's label. On Tickee's network alone (the normal case) there is one address and one check, exactly as today (RQ-05).
   - **Why**: AC-05 as written, the stand-in attached to `c4-infra.faito` **too**, then KOs both by name and at its address on Faito's network. Today the two addresses are glued into a name nc can't resolve, which passes.
   - **Rejected**: keep `:182` as it is and run AC-05 as 0023's mutation literally (the stand-in on `c4-infra.faito` instead of Tickee's network). The glued address would then KO with nc's "can't resolve" message (choice 2), not with "succeeded".
4. **PA-02's KO: a check of its own, and the part goes on** *(to confirm)*.
   - **The check**: the first check of part `tickee`, `Faito's network c4-infra.faito is there (Faito registered: bash $FAITO_DIR/deploy-dev.sh, or bash register-app.sh --app faito)`, with docker's message under its KO.
   - **Why the part goes on**: the negative checks KO on their own, naming the network. AC-02's copy renames the network everywhere, so stopping the part would hide the two KOs that AC-02 asks for.
   - **RQ-05**: the existing checks keep their labels. This line is PA-02 A's KO.
   - **Rejected**:
     - the remedy printed only in the negative checks' KO, with no new check (strictly today's list of checks, but the prerequisite is shown three times, under a reachability label);
     - stopping after the KO, as the stand-in precedent does (hides AC-02's KOs).
5. **`:187` and `:213`**.
   - **`:187`**: the command's status is read, and a failure is a KO naming the command (`docker ps failed`) with its message.
   - **`:213`**: a failure of the model is a KO naming the command (`docker compose config failed`) with its message. The dev model must also have the reverse proxy on `c4-infra.faito` (`has("c4-infra.faito")`), otherwise the KO says the model lacks it. Only then is the `host.docker.internal` alias checked. The label is unchanged.
   - **`fails`** is removed: it has no caller left, and `:213` keeps its meaning (RQ-05).
6. **AC-03 on the real stack, once, by hand** *(to confirm: it changes the developer's stack for about 30 s)*.
   - **Automatically**, the "without Faito's network" variant proves AC-03: the copy sees no Faito network.
   - **At verification**, the literal case on the real stack:
     - `bash networks.sh remove faito`;
     - `bash tests/0007-dev.sh tickee`;
     - `bash register-app.sh --app faito`, which restores the network;
     - then `bash tests/0007-dev.sh networks`.
   - **The condition**: step 0 (d) shows that only the five shared services are on `c4-infra.faito` in dev. If anything else is there, this check is dropped.
   - **Rejected**: the copy alone (sound, but it isn't the intent's step, "Faito not registered").

## Files

| File | Change | For |
| --- | --- | --- |
| `tests/0034-negative-checks.sh` | New, frozen after step 1. `# covers: tests/0007-dev.sh`. Runs `tests/0007-dev.sh` four times (choice 1). Keeps each log and exit status. Asserts a KO line by its label, and its cause among the indented lines under it.<br>**Without Faito's network**: a copy with `c4-infra.faito` → `c4-infra.0034-no-such-app`, parts `tickee guard`. Expects:<ul><li>the copy names the new network;</li><li>a KO naming `c4-infra.0034-no-such-app` and `register-app.sh --app faito`;</li><li>both AC-07 negative checks KO, each cause naming the network;</li><li>no `ok - AC-07: from c4-infra.0034-no-such-app` line;</li><li>the dev alias check (`:213`'s label) KO, its cause naming the network;</li><li>exit 1.</li></ul>**Without the probe image**: a copy with `alpine:3` → `alpine:0034-no-such-tag`, part `tickee`. Expects the control and both negative checks KO, each cause naming `alpine:0034-no-such-tag`, and exit 1.<br>**The stand-in on Faito's network too**: the test as it is, with a `docker` wrapper first on `PATH` (the real docker found with `command -v` beforehand, as `tests/lib/argv-log.sh` does). Once `docker run -d --name tickee.network-standin …` succeeds, the wrapper connects the stand-in to `c4-infra.faito`. Part `tickee`. Expects the by-name check and one address check KO, each cause saying `succeeded`, and exit 1.<br>**Docker failing**: the same wrapper fails `ps … name=^tickee.network-standin$` and `compose config --format json` (exit 1, a message of its own). Parts `tickee guard`. Expects:<ul><li>`the stand-in is removed` KO naming `docker ps`;</li><li>the dev alias check KO naming `docker compose config`;</li><li>both AC-07 negative checks `ok` (the twin: the real isolation passes);</li><li>exit 1.</li></ul>No `sort`. Works under bash and Git Bash (`\r` stripped from the logs). | RQ-01 to RQ-04, AC-02 to AC-06 |
| `tests/0007-dev.sh` | Modified.<br>**The probe**: `PROBE_IMAGE=alpine:3`; `probe` shared by the control and the negative checks, with their verdicts (choice 2).<br>**PA-02**: the first check of part `tickee` (choice 4).<br>**By address**: the stand-in's addresses one per line, one check each, with today's label (choice 3).<br>**`:187`, `:211-213`**: as choice 5.<br>**`fails`**: removed.<br>**Header**: parts `tickee` (`:13-16`) and `guard` (`:17-20`) say what a negative check accepts, and that Faito's network is required.<br>Labels, parts, order and `# covers:` otherwise unchanged. | RQ-01 to RQ-05, AC-01 to AC-06 |
| `docs/intent/0034-…/plan.md` | New: this plan, then its *Deviations* and `## Verification`. | — |
| `docs/intent/0034-…/intent.md` | Status `planned`, then `delivered` (`/sdlc-ship`). | — |
| `docs/intent/README.md` | 0034's index row follows the status. | — |
| `docs/intent/HANDOVER.md` | At delivery, the "Left open" line on `fails` goes (it is now 0034). | — |

The README, `CLAUDE.md` and `tests/lib/` are unchanged. A suite-wide convention for negative checks is the spec's PA-01 follow-up, in its own change.

## Order of work

**Batch** (the product owner, 2026-10-28): 0032, 0034 and 0033 are verified together. 0032 is committed on `main` itself, which stays local until the batch's push; 0034 and 0033 are merged in that order into `batch-0032-0034-0033`, from `main`. This intent's review round runs on its own commits. The verification command runs once, `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --all` on the integration head, from the main tree: this intent's verification and the milestone before the push. Its verifier gets that log; the mutation checks run as written below. A failure is attributed by rerunning the failing test on this intent's branch, and fixed there. `/sdlc-ship` delivers the three in the batch's order, then one push of `main`, validated by the product owner.

0. **Setup and facts**.
   - **Setup**:
     - check out `0034-isolation-checks-pass-without-network`, then `git pull` and `git merge main` (a no-op unless `main` moved);
     - the dev stack running (`bash up.sh`), Faito registered (`bash ../faito/deploy-dev.sh`), `jq` installed;
     - baseline: `TMPDIR=~/.cache/c4-infra-tests bash tests/0007-dev.sh > <scratchpad>/0034-baseline.log`, expecting `every check passed`. Its labels are AC-01's reference.
   - **Facts**: one scratch script in the scratchpad (not committed), on two throwaway networks `c4-0034-facts-a` and `-b`. A responder `c4-0034-facts-standin` (`caddy:2.11.4-alpine caddy respond --listen :7080`) runs on `a`. A trap removes them. Each command's output, exit status and duration are recorded.
     - **(a) Docker**: `docker version --format '{{.Client.Version}} {{.Server.Version}}'`, `docker compose version`.
     - **(b) The docker CLI's exit status and message** for:
       - a network that doesn't exist: `docker run --rm --network c4-0034-no-such-net alpine:3 true`, and `docker network inspect c4-0034-no-such-net`;
       - an image tag that doesn't exist: `docker run --rm alpine:0034-no-such-tag true`, its message online (and offline, if the workstation allows it);
       - a daemon that doesn't answer: `DOCKER_HOST=unix:///nonexistent/0034.sock` on `docker run --rm alpine:3 true`, `docker ps -aq`, `docker network inspect c4-infra.faito` and `docker compose config --format json`. Does compose need the daemon?
       - a command the image doesn't have, or can't run: `docker run --rm alpine:3 no-such-command` (127?) and `… /etc/hostname` (126?).
     - **(c) busybox nc in `alpine:3`**:
       - is the image present (`docker image inspect -f '{{.Id}} {{.Created}}' alpine:3`) or pulled? Its `/etc/alpine-release`, busybox's version;
       - with the probe of choice 2 (`sh -c 'nc -vv -z -w 3 "$1" "$2" 2>&1; echo "nc exit $?"'`), nc's status and words for:
         - success (from `a`, by name, `:7080`);
         - a refused connection (from `a`, by name, `:7081`);
         - a name that doesn't resolve (from `b`, by name: today's by-name case);
         - Docker's isolation (from `b`, the responder's address on `a`: today's by-address case; timed out? after how long?);
         - a glued pair of addresses (`<a address><b address>`);
       - `-vv` versus `-v` (busybox prints a refusal only from the second `-v`, to measure);
       - inside the container, `nc` not found (`sh -c 'no-such-nc …; echo "nc exit $?"'`).
     - **(d) The real stack, read only**:
       - `c4-infra.faito` exists, labelled `c4-infra.app=faito`;
       - the containers on it, the five shared services alone or not (choice 6);
       - `docker compose config --format json | jq '.services["reverse-proxy"].networks["c4-infra.faito"]'`, dev's value.
     - **(e) Two networks**: the responder connected to `b` too (`docker network connect`). Then `{{range …}}{{.IPAddress}}{{end}}` (glued?) against `{{"\n"}}` (one per line). From `b`: by name, at its address on `b`, at its address on `a`.
   - **Then, by the answers**:
     - **The by-address case**: Docker's isolation (c, by address) fails otherwise than refused or timed out (for example "Host is unreachable") → stop. RQ-01 can't hold as written: spec v2 through Stage 2 before step 1.
     - **nc's words**:
       - nc gives no words for a case even with `-vv` → choice 2 falls back to (B) for that case (`nc exit 1`). This is recorded and the engineer is told;
       - other statuses or words → the constants follow the measurement. The frozen test doesn't read nc's words.
     - **Faito's network**: something besides the five shared services is on `c4-infra.faito` (d) → choice 6's manual check is dropped.
     - **Daemon errors**: a docker error that exits 1 (b) is recorded. Choice 2 doesn't read docker's status.
   - skill: none — check: the answers recorded under *Deviations*; `git status --short` empty; `docker network ls` without `c4-0034-*`.
1. **Failing test**: `tests/0034-negative-checks.sh`.
   - skill: none — check: `bash tests/0034-negative-checks.sh` exits 1, and its KOs are exactly the bug's:
     - **without Faito's network**: the PA-02 KO is missing; both negative checks and the dev alias check print `ok`. The exit 1 holds already, because the copy's demo alias check KOs;
     - **without the probe image**: both negative checks print `ok`. The control's KO holds already;
     - **on Faito's network too**: the address check prints `ok`, on the glued address. The by-name KO (`it succeeded`) holds already;
     - **docker failing**: `the stand-in is removed` and the dev alias check print `ok`, and the run exits 0. The twin's two `ok` hold.
   - Also: `bash tests/0019-collation.sh` passes, and `bash tests/0007-dev.sh` still prints `every check passed` (the file is untouched).
   - Commit `test(0034): tests/0007-dev.sh's negative checks pass without Faito's network, the probe image or docker` alone. Freeze it: add `tests/0034-negative-checks.sh` to `.claude/frozen-tests.local`.
2. **Fix** `tests/0007-dev.sh`, as in *Files*.
   - skill: none — check:
     - `bash -n tests/0007-dev.sh`;
     - `git diff HEAD -- tests/0034-negative-checks.sh` is empty;
     - `bash tests/0034-negative-checks.sh` prints `every check passed`;
     - `TMPDIR=~/.cache/c4-infra-tests bash tests/0007-dev.sh` prints `every check passed`. Its `ok -` lines are the baseline's, with addresses masked (`sed -E 's/[0-9]+(\.[0-9]+){3}/<ip>/g'`), plus the PA-02 line;
     - `bash tests/0007-dev.sh tickee`: five runs out of five `every check passed` (the probes' timing);
     - `bash tests/0019-collation.sh` passes.
   - By hand, recorded:
     - `DOCKER_HOST=unix:///nonexistent/0034.sock bash tests/0007-dev.sh tickee` exits 1. There is no `ok - AC-07: from c4-infra.faito` line, and each negative check's KO shows docker's daemon message (RQ-02's daemon error);
     - a copy whose address list is `999.0.0.1`: that check KOs with nc's message, not `ok` (choice 2's words).
   - Commit `fix(0034): tests/0007-dev.sh's negative checks pass only on a failed connection from c4-infra.faito`.
3. **Verification**, after `git merge main` if `main` moved.
   - **The run**: `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --changed --all` selects:
     - `tests/0007-dev.sh` (its own file);
     - `tests/0019-collation.sh` (it declares `tests/`);
     - `tests/0034-negative-checks.sh` (its own file, and it declares `tests/0007-dev.sh`);
     - no stand-in or facts test.

     Expected: `verification passed (--changed: 3 of 73 tests)`, and no `uncovered:`.
   - **The mutation check**:
     - `git show main:tests/0007-dev.sh > tests/0007-dev.sh`, then `bash tests/0034-negative-checks.sh`: exit 1, with step 1's KOs;
     - then `git checkout -- tests/0007-dev.sh`, and `git status --short` is empty.
   - **Choice 6, if confirmed**: `bash networks.sh remove faito; bash tests/0007-dev.sh tickee; bash register-app.sh --app faito`. Expected: the PA-02 KO, no `ok - AC-07: from c4-infra.faito` line, exit 1. Then `bash tests/0007-dev.sh networks` prints `every check passed`.
   - **Git Bash**: this workstation runs Linux, so it is reported "not verifiable here".
   - **`/sdlc-verify 0034`**: bootstrap, so one round and the bugs pass. The risk is standard: no security pass, no `simplify`. Its evidence goes into `## Verification`; commit `plan: verification of 0034`.
   - skill: sdlc-verify — check: `verification passed`.
   - Then `/sdlc-ship 0034`: bootstrap, the local merge of the branch into `main`.

## Risks

- **The frozen test leans on the text of `tests/0007-dev.sh`**: `c4-infra.faito`, `alpine:3`, the labels, and `:187`'s and `:211`'s commands → RQ-05 keeps the labels, and the fix keeps the commands (choice 1). A later change to any of them reruns it (it declares `tests/0007-dev.sh`) and fails closed: an expected KO goes missing.
- **nc's words change** with the floating `alpine:3` (busybox, musl) → the real isolation's checks KO with nc's message: they fail closed, and the words sit in one constant each. A false `ok` isn't possible: a connection is always a KO.
- **Docker's isolation answers otherwise than RQ-01's reasons** → step 0 measures it, and stops for a spec v2 if so.
- **Git Bash isn't measured on this workstation** → the code follows the suite's rules:
  - `MSYS_NO_PATHCONV=1` on the probe;
  - `\r` stripped from docker's output;
  - the wrapper runs the docker found with `command -v`, as `argv-log.sh` does under Git Bash.

  The evidence reports it "not verifiable here" (AC-07).
- **The by-name probe goes through Docker's DNS**, which forwards unknown names to the host's resolvers. A resolver that answers every name only changes the reason (refused or timed out), never the verdict.
- **The variant without the probe image asks Docker Hub** about a tag that doesn't exist, 3 times per run. Offline, docker's first line still names the image (step 0 (b)).
- **Duration**: the new test runs part `tickee` four times and part `guard` twice, about 1.5 min in lane 1 → measured at step 2, and reported in the evidence.
- **The variants register Tickee and start the stand-in**, as the test itself does. An interrupted run may leave `tickee.network-standin` → each run starts with `docker rm -f` (`:163`), and the copy's trap cleans up.
- **The mutation check rewrites `tests/0007-dev.sh` in the working tree** → it is restored by `git checkout`, then `git status --short` is empty. The file isn't frozen.
- **Choice 6 removes Faito's network** for the length of one part → only on step 0 (d)'s answer. The restore is the command part `networks` runs anyway.
- **The frozen test proves wrong at step 2** (for example, a wording it asserts) → a deviation to ask about: unfrozen with the product owner's approval, as in 0018 and 0025.

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| AC-01 | automated test | `TMPDIR=~/.cache/c4-infra-tests bash tests/0007-dev.sh` prints `every check passed`; its labels are the baseline's (addresses masked) plus PA-02's line (step 2). `bash tests/0007-dev.sh tickee` passes 5 out of 5. It also passes within AC-07's run. |
| AC-02 | automated test | `tests/0034-negative-checks.sh`, without Faito's network: both negative checks KO naming `c4-infra.0034-no-such-app`, exit 1. |
| AC-03 | automated test + manual check | The same variant: PA-02's KO names the network and `register-app.sh --app faito`; no `ok - AC-07` negative line; exit 1. Choice 6 at step 3, if confirmed. |
| AC-04 | automated test | `tests/0034-negative-checks.sh`, without the probe image: the control and both negative checks KO naming `alpine:0034-no-such-tag`. |
| AC-05 | automated test | `tests/0034-negative-checks.sh`, the stand-in on Faito's network too: by name and at its address there, KO `succeeded`. |
| AC-06 | automated test | `tests/0034-negative-checks.sh`:<ul><li>docker failing: `the stand-in is removed` KO naming `docker ps`; the dev alias check KO naming `docker compose config`; the AC-07 negative checks `ok`;</li><li>without Faito's network: the dev alias check KO, the model lacking it.</li></ul>Also step 2's daemon error, by hand. |
| AC-07 | command | `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --changed --all` prints `verification passed (--changed: 3 of 73 tests)`, with no `uncovered:`. Git Bash: "not verifiable here". |
| The bug is reproduced | mutation check | `main`'s `tests/0007-dev.sh` in the working tree makes `bash tests/0034-negative-checks.sh` exit 1, with step 1's KOs (at step 1, and again at step 3). |

## Deviations

<!-- filled during implementation: date — what — why — impact on files or proof -->

- 2026-10-28 — step 0. Baseline: `TMPDIR=~/.cache/c4-infra-tests bash tests/0007-dev.sh` → `every check passed` (38 ok). Facts (two throwaway networks `c4-0034-facts-a`/`-b`, a responder `caddy:2.11.4-alpine caddy respond --listen :7080` on `a`; docker 29.8.2 client, 29.6.1 server, compose 5.3.0; `alpine:3` present, Alpine 3.24.3, BusyBox v1.37.0):
  - (b) `docker run` on a missing network: exit 125, `network c4-0034-no-such-net not found`; `docker network inspect` of it: exit 1; a missing image tag: exit 125, `…alpine:0034-no-such-tag: not found`; the daemon away (`DOCKER_HOST=unix:///nonexistent/0034.sock`): `docker run` and `docker ps` exit **1** (`failed to connect to the docker API…`), `docker compose config` exits 0 (it needs no daemon); a command the image lacks: 127; a file not executable: 126.
  - (c) the probe `sh -c 'nc -vv -z -w 3 "$1" "$2" 2>&1; echo "nc exit $?"'`: success → `… open`, `nc exit 0`; refused → `nc: <name> (<ip>:7081): Connection refused`, `nc exit 1`; a name unresolved (from `b`) → `nc: bad address '<name>'`, `nc exit 1`; Docker's isolation by address (from `b`, the responder's address on `a`) → `nc: <ip> (<ip>:7080): Operation timed out`, `nc exit 1`, after about 3 s (`-w 3`): RQ-01 holds as written, no spec v2; glued addresses → `bad address '<ip><ip>'`, `nc exit 1`; `-v` prints no refusal (only `-vv` does); `nc` not found in the container → `sh: no-such-nc: not found`, `nc exit 127`.
  - (d) `c4-infra.faito`: labelled `c4-infra.app:faito`, holding the five shared services only (mailpit, rabbitmq, grafana-lgtm, keycloak, reverse-proxy): choice 6's manual check stays; dev's model: the reverse proxy on `c4-infra.faito` with `{}` (no alias).
  - (e) on two networks: `{{range …}}{{.IPAddress}}{{end}}` glues them (`172.26.0.2172.27.0.2`); `{{"\n"}}` gives one per line; from `b`, the responder connected to `b` too answers by name (`open`), while its address on `a` times out.
  - Hence choice 2's accepted reasons: by name `bad address`, `Connection refused`, `Operation timed out`; by address `Connection refused`, `Operation timed out`.
- 2026-10-28 — step 1: `tests/0034-negative-checks.sh` on the unfixed `tests/0007-dev.sh` → exit 1, `11 check(s) failed`, exactly the bug's: without Faito's network, no PA-02 KO, both negative checks and the dev alias check `ok`; without the probe image, both negative checks `ok` (the control KOs already); the stand-in on Faito's network too, the address check `ok` (the glued address), the by-name KO already there; docker failing, the stand-in's removal and the dev alias check `ok`, exit 0. Frozen (`.claude/frozen-tests.local`). The by-address label is matched by its address (`[0-9]+(\.[0-9]+){3}:7080 can't be reached$`), so the by-name check can't stand in for it.
- 2026-10-28 — step 2 (565d6e8): `tests/0034-negative-checks.sh` → `every check passed` (19 ok), unchanged; `tests/0007-dev.sh` → `every check passed`, its `ok` lines the baseline's (addresses masked) plus the PA-02 line; `tests/0007-dev.sh tickee` five times → `every check passed`; `tests/0019-collation.sh` → passed. By hand: `DOCKER_HOST=unix:///nonexistent/0034.sock bash tests/0007-dev.sh tickee` → exit 1, no `ok - AC-07: from c4-infra.faito`, each negative check's KO showing docker's daemon message; a copy whose only address is `999.0.0.1` → that check KOs `nc failed for another reason than Connection refused|Operation timed out: nc: bad address '999.0.0.1'`. Mutation: `main`'s `tests/0007-dev.sh` in the tree → `tests/0034-negative-checks.sh` exit 1, `11 check(s) failed` (step 1's), restored.
- 2026-10-28 — choice 6, AC-03 on the real stack: `bash networks.sh remove faito` (the network gone), `bash tests/0007-dev.sh tickee` → exit 1, the PA-02 KO (`Error response from daemon: network c4-infra.faito not found`), no `ok - AC-07: from c4-infra.faito`; `bash register-app.sh --app faito` → exit 0; `bash tests/0007-dev.sh networks` → `every check passed`. Observed meanwhile, outside this intent: with `c4-infra.faito` removed by `networks.sh remove faito`, `bash register-app.sh --app tickee` failed (`could not find a network matching network mode c4-infra.faito`): the shared services were recreated from a model that still names Faito's network. Pre-existing (`networks.sh`); a follow-up if an application's network may go missing while it stays registered.
- 2026-10-28 — the review round (bootstrap: one; `code-review high` on dd3cfb1..565d6e8, in the batch). Fixed in `tests/0007-dev.sh` (d1a782c): `unreachable` matched the accepted reasons anywhere in the probe's output, docker's lines included: now nc's own line only (`^nc: .*(…)`); a failed `docker inspect` of the stand-in left `has an address (none)` without a cause: its error printed; with the model unread, the dev alias check's label said `(no alias)`: it says `(its model unread)`. With the product owner's approval (2026-10-28), `tests/0034-negative-checks.sh` unfrozen and strengthened (the next commit), then frozen again: in the variant without Faito's network, the causes were found in the KO labels themselves, which hold the network's name (they couldn't fail): the cause is now read under each KO (`network c4-infra.0034-no-such-app not found`, `reverse proxy on c4-infra.0034-no-such-app`); the address label's regex used an interval and an escaped dot through `awk -v` (old mawk, gawk's warning): `[0-9.]+:7080 can't be reached$`. Then: on the fix → `every check passed`; `main`'s `tests/0007-dev.sh` → `11 check(s) failed`. Answered: `host.docker.internal` written in the dev alias check rather than read from `INFRA_HOST` (pre-existing); Tickee registered again by each of the four variants (about 1 min 30, the stack left as it was).

## Verification

### Verification — 98ff2ad (integration 24e6481, which contains it)

- KO first: the batch's verification command ended `run.sh exit 1` both times at 24e6481; every failed test passed when run alone at the same commit, and none covers 0034's files (`tests/0007-dev.sh`, `tests/0034-negative-checks.sh`).
  - Run 1, two stand-in lanes: `total: 2527.0 s for 79 test(s)`, FAILED 0003-dev-routes, 0002-accounts.stand-in, 0016-realms, 0016-themes, 0017-export-realm, 0026-stack-bounds (the dev Keycloak found stopped mid-run, a Docker Hub CDN lookup failing in a stand-in, a POST answered 000, Pyroscope still a raft Follower); alone at 24e6481: `every check passed` each. Its log was lost when the workstation froze.
  - Run 2, one stand-in lane (`SUITE_DOCKER_MEMORY=1`, the product owner's choice after the freeze): `total: 3636.9 s for 79 test(s)`, FAILED 0024-db-image-change.stand-in (`registry-1.docker.io` unreachable) and 0033-limits-facts.stand-in (0033's facts, a timing margin); alone at 24e6481: `every check passed` both. Log `~/.cache/c4-infra-tests/batch2/all-24e6481.log`: `tests/0007-dev.sh` `every check passed` (39 ok), `tests/0034-negative-checks.sh` `every check passed`.
- Verification command, the change's own (AC-07), at 9afcd88 in a throw-away worktree: `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --changed main --all` → `verification passed (--changed: 5 of 74 tests)`, no `uncovered:` (0007-dev, 0034-negative-checks, 0016-no-real-provider, 0019-collation, 0032-demo-github-only: 0032's guard covers `tests/`, hence 5, not the plan's 3).
- Risk tier: standard (a test of the dev stack).
- Reviews: bootstrap mode: 1 round, on 0034's own commits (`code-review high` on dd3cfb1..565d6e8); bugs 5 fixed (3 in `tests/0007-dev.sh`, d1a782c; 2 in the frozen test, 98ff2ad, unfrozen with the product owner's approval) / 2 answered (the `host.docker.internal` alias, pre-existing; Tickee registered again by each variant); no security pass (standard risk).
- Mutation check (bug): `tests/0034-negative-checks.sh` against main's `tests/0007-dev.sh` → exit 1, `11 check(s) failed`, the bug's reasons (the session's, and the verifier's own at bfcf997: without the network no PA-02 KO and both negative checks `ok`; without the image both `ok`; the glued addresses `ok`; docker failing, the removal and the alias check `ok`).
- Verifier: 6/7 criteria OK, 0 KO, AC-07 not verifiable by it (told not to run `run.sh`), then OK by the session's run above: 7/7 — table below. Its own checks: the daemon away (`DOCKER_HOST` on a missing socket) → `9 check(s) failed`, PA-02's KO naming the API error, no `ok - AC-07`; the review round's points read in the diff.
- Not verifiable here: the run under Git Bash (the workstation runs Linux).
- Files outside the plan: none.
- Pre-existing findings: Tickee's registration fails while Faito's network is gone (`networks.sh`, recorded at AC-03's run).
- Details left (not KO): with two addresses, the label `has an address (…)` spans two lines (`tests/0007-dev.sh:215`); the alias check's label says `(no alias)` when the model lacks the network (the line under the KO names the cause, `:259`); the comment at `:211` restates the template; with the daemon away there is no by-address check (`has an address (none)` KOs instead); `BY_ADDRESS` (`[0-9.]+`) also matches a glued address, harmless: the fix gives it `bad address`.

| Criterion | Result | Evidence |
| --- | --- | --- |
| AC-01 | OK | `tests/0007-dev.sh` at 24e6481: `every check passed`, 39 ok: the unfixed run's 38 lines plus `ok - Faito's network c4-infra.faito is there (…)`, the labels unchanged |
| AC-02 | OK | `ok - without Faito's network: the negative check by name KOs, naming it`, `… by address KOs, naming it`, `… exit 1` (docker's `network … not found` read under each KO) |
| AC-03 | OK | `ok - … a KO names it and register-app.sh --app faito`, `ok - … no ok from it`; on the real stack (Deviations): the tickee part exit 1, PA-02's KO, no `ok` from Faito's network |
| AC-04 | OK | `ok - without the probe image: the control KOs, naming it`, `… by name …`, `… by address …`, `… exit 1` |
| AC-05 | OK | `ok - the stand-in on Faito's network too: by name, KO succeeded`, `… at one of its addresses, KO succeeded`, `… exit 1` |
| AC-06 | OK | `ok - docker failing: the stand-in's removal KOs, naming docker ps`, `… the dev alias check KOs, naming docker compose config`, both negative checks still `ok`; by hand, the daemon away: `9 check(s) failed`, each naming docker's error |
| AC-07 | OK | `--changed main --all` at 9afcd88 → `verification passed (--changed: 5 of 74 tests)`, no `uncovered:` |
- The product owner at delivery (2026-10-28): the batch's verification accepted with the KOs above (every failed test passing alone at 24e6481).

### After deployment — deploy-demo run 40808682088 on `main` 9d69e9d (2026-10-29 UTC, the product owner's push), success

- Nothing of this change is deployed (documents and tests): nothing to check on the host.
