# Plan: The dev stack is reachable from the local network

- Spec: [v1](spec.md)
- Status: approved
- Branch: main (grouped pass of 2026-10-21)
- Approved: 2026-10-22, Jérôme Wacongne (engineer, product owner and tech lead), after two rounds of cross-plan coherence review
- Builds on: nothing (first of the pass: 0001 → 0004 → 0003 → 0005 → 0006 → 0002 → 0007)

## Starting point

- `compose.yml` publishes `80`, `443`, `1025`, `8025`, `5672`, `15672`, `3000`, `4317`, `4318` without an address: `docker ps` shows `0.0.0.0:…` and `[::]:…` for each (checked 2026-10-21).
- This workstation's hosts file holds `127.0.0.1 host.docker.internal`, and `powershell.exe … GetHostAddresses('host.docker.internal')` returns `127.0.0.1`; Git Bash has no `getent`.
- The repository has no test and no verification command yet: this plan adds both (`tests/`, `tests/run.sh`), which the following plans extend.

## Files

| File | Change | For |
| --- | --- | --- |
| `tests/lib/assert.sh` | new: `check <description> <command…>` (prints `ok`/`KO`, counts failures), `finish` (exit 1 when a check failed) | all ACs |
| `tests/lib/stubs.sh` | new: `stub_path <dir> [docker] [getent] [powershell.exe]` writes the named fakes into `<dir>`, for `PATH="<dir>:$PATH"`: `docker` logs its arguments to `$STUB_LOG`, prints nothing, exits 0; `getent` and `powershell.exe` answer `$STUB_ADDRESS` (`getent` in `ahostsv4`'s layout) | AC-5 |
| `.gitignore` | modified: `.claude/*.local` (the frozen-tests list of `sdlc-plan`, and any other local state, never committed) | bookkeeping |
| `tests/0001-loopback-ports.sh` | new: the reproducing test, three parts selectable by argument (`config`, `running`, `resolution`; all by default) | AC-1, AC-5 |
| `tests/run.sh` | new: runs `bash -n` on every `*.sh` of the repository, then every `tests/[0-9][0-9][0-9][0-9]-*.sh` except `*.stand-in.sh`; `--all` runs the `*.stand-in.sh` too (added by 0003) | verification |
| `CLAUDE.md` | modified: a "Verification" line: `bash tests/run.sh` with the dev stack running (`jq` needed), `bash tests/run.sh --all` before a change to the demo host | verification |
| `compose.yml` | modified: every `ports` entry prefixed with `127.0.0.1:` | REQ-1, AC-1, AC-2 |
| `up.sh` | modified: first thing after `cd`, before `env.sh`: stop with REQ-4's message unless every IPv4 address `host.docker.internal` resolves to is `127.0.0.1` (`getent ahostsv4` when present, else `powershell.exe … [System.Net.Dns]::GetHostAddresses`) | REQ-4, AC-5 |
| `README.md` | modified: "Ports on the host" column says `127.0.0.1` only; Prerequisites: `127.0.0.1 host.docker.internal` in the hosts file and Docker Desktop's "Add the *.docker.internal names to the host's etc/hosts file" turned off; testing from another device is not supported (0001 PA-2) | REQ-1, REQ-4 |
| `docs/intent/0001-dev-stack-reachable-from-the-network/plan.md` | new: this plan (status `approved` at the engineer's and tech lead's gate) | bookkeeping |
| `docs/intent/0001-dev-stack-reachable-from-the-network/intent.md` | modified: status `planned` at approval | bookkeeping |
| `docs/intent/README.md` | modified: index row 0001 → `planned` | bookkeeping |

## Order of work

1. **Failing test.** First add `.claude/*.local` to `.gitignore` (commit `chore(0001): ignore Claude Code's local state`, alone), so that `.claude/frozen-tests.local` can never be committed. Then write `tests/lib/assert.sh`, `tests/lib/stubs.sh`, `tests/0001-loopback-ports.sh` and `tests/run.sh`, and commit them alone, staged by path (`git add tests/`, never `git add -A`), as `test(0001): published ports on every interface, and up.sh starting whatever host.docker.internal resolves to`. The test:
   - `config`: `docker compose config --format json | jq` lists every published port of every service; each must have `host_ip` `127.0.0.1`, and the nine ports of REQ-1 must all be there (so that dropping a port doesn't pass);
   - `running`: `docker ps --filter name='^c4-infra\.' --format '{{.Names}} {{.Ports}}'`: every mapping (`<ip>:<port>->…`) starts with `127.0.0.1:`, none with `0.0.0.0:` or `[::]:`;
   - `resolution`: stubs in a temporary directory, `STUB_ADDRESS=192.168.1.20`, `PATH="$stubs:$PATH" bash ./up.sh`; expect a non-zero exit, a message naming `192.168.1.20`, the line `127.0.0.1 host.docker.internal` and Docker Desktop's option, and an empty `$STUB_LOG` (no `docker` call at all: "starts nothing"). Two variants, since up.sh takes `getent` when there is one: **PowerShell branch** — `stub_path <dir> docker powershell.exe` only (Git Bash has no `getent`, so up.sh asks `powershell.exe`; on a machine with a real `getent` this variant is skipped with a message); **getent branch** — `stub_path <dir> docker getent powershell.exe`. Each variant also runs with `STUB_ADDRESS=127.0.0.1` and checks that up.sh gets past the check (the stub log shows `docker compose` calls), so that the check doesn't refuse the good case;
   — skill: none — check: `bash tests/0001-loopback-ports.sh; echo "exit=$?"` shows `KO` on all three parts for the expected reasons (`host_ip` missing, `0.0.0.0:` mappings, up.sh calling `docker compose up`) and `exit=1`. Then write the path into `.claude/frozen-tests.local` (sdlc-plan §4).
2. **Ports on the loopback** in `compose.yml` (`- 127.0.0.1:80:80`, … for the nine ports). — skill: none — check: `bash tests/0001-loopback-ports.sh config`.
3. **up.sh refuses a non-loopback `host.docker.internal`** (REQ-4). The message, on stderr:
   `host.docker.internal resolves to <addresses>, not 127.0.0.1. The stack publishes its ports on the loopback only: this machine's browser and JVMs would not reach it.` then how to fix it: turn off Docker Desktop's option (Settings > General, "Add the *.docker.internal names to the host's etc/hosts file"), keep the single line `127.0.0.1 host.docker.internal` in `C:\Windows\System32\drivers\etc\hosts` (`/etc/hosts` elsewhere), run up.sh again. — skill: none — check: `bash tests/0001-loopback-ports.sh resolution`.
4. **Apply it to the running stack**: `bash up.sh` (recreates every published service: about a minute of Keycloak downtime, expected). — skill: none — check: `bash tests/0001-loopback-ports.sh` (all three parts) and `MSYS_NO_PATHCONV=1 docker run --rm --add-host host.docker.internal:host-gateway alpine:3 sh -c 'nc -z -w 3 host.docker.internal 1025 && nc -z -w 3 host.docker.internal 443'` exits 0 (a container still reaches the loopback-published SMTP and HTTPS ports through `host.docker.internal`, REQ-3).
5. **Docs and verification command**: README (ports, prerequisites), `CLAUDE.md` verification line. — skill: none — check: `bash tests/run.sh` passes and `grep -n '127.0.0.1 host.docker.internal' README.md` finds the prerequisite.
6. **End-to-end proofs** (manual, with Faito running). Start Faito (until Faito 0020 its gateway doesn't start from its jar, hence `spring-boot:run`), each in its own Git Bash terminal:
   - `bash ../faito/deploy-dev.sh` (registration and database);
   - gateway: `export JAVA_HOME=~/.sdkman/candidates/java/25.4.4.1+1-graalce; set -a; source ../faito/.env; set +a; cd ../faito/backend && ./mvnw -q -pl gateway -am install -DskipTests && ./mvnw -pl gateway spring-boot:run`;
   - REST API: the same with `-pl faito-api`;
   - front end: `cd ../faito/frontend/angular && npm start`.

   Then AC-2, AC-3 and AC-4 below. — skill: none — check: the three proof lines, results pasted in the PR.

## Risks

- Browsers resolve `faito.dev.localhost` to `::1` first, which is no longer published → they fall back to `127.0.0.1` at once (connection refused, not a timeout); AC-3's manual login proves it. If a browser stalls, publishing `[::1]` as well would need the spec's agreement (REQ-1 names `127.0.0.1`).
- A container reaching a published port through `host.docker.internal` (Keycloak sending mail to `host.docker.internal:1025`) depends on Docker Desktop forwarding the host gateway to the workstation's loopback → step 4's `nc` check and AC-4. On Linux with Docker Engine (not Desktop) it doesn't hold: the README's prerequisites already name Docker Desktop.
- `powershell.exe` is slow (~1 s) and prints `\r` → the check strips `\r` and costs one call per `up.sh`.
- Docker Desktop rewriting the hosts file after the fix → up.sh refuses with the fix in its message (REQ-4, by design).
- Recreating the stack in step 4 drops Keycloak for about a minute → done once, while Faito's processes are stopped.

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| AC-1 | automated test | `bash tests/0001-loopback-ports.sh config` and `… running`. Mutation check (configuration-only fix): `sed -i 's/127.0.0.1:8025:8025/8025:8025/' compose.yml; bash tests/0001-loopback-ports.sh config; echo "exit=$?"; git checkout -- compose.yml` shows `KO` for 8025 and `exit=1` |
| AC-2 | command + manual check | Command: `ip=$(powershell.exe -NoProfile -Command "(Get-NetIPConfiguration \| Where-Object IPv4DefaultGateway \| Select-Object -First 1).IPv4Address.IPAddress" \| tr -d '\r'); for p in 443 8025 15672; do curl --ssl-no-revoke -sk --connect-timeout 3 "https://$ip:$p/" -o /dev/null; echo "$p exit=$?"; done` prints `exit=7` (connection refused) for each. Manual: from a phone or another computer on the same network, `nc -zv <that ip> 443` (or a browser on `https://<ip>/`, `http://<ip>:8025/`, `http://<ip>:15672/`) is refused |
| AC-3 | manual check | Faito running (step 6): log in on `https://faito.dev.localhost/fr/`, log out (back on `/fr/`, anonymous); log in again, then in `https://host.docker.internal/auth/admin/` → realm `faito` → Sessions → sign the user out; the same browser on `https://faito.dev.localhost/gateway/me` (or the page's user menu) shows an anonymous user |
| AC-4 | manual check | Faito running: register a new user on Faito's login page; the verification e-mail shows in `https://host.docker.internal/mailpit/` |
| AC-5 | automated test | `bash tests/0001-loopback-ports.sh resolution` (the PowerShell branch and the `getent` branch, each stubbed to answer `192.168.1.20`: exit ≠ 0, message, no `docker` call; and `127.0.0.1` gets past the check) |

## Deviations

<!-- filled during implementation: date — what — why — impact on files or proof -->

- 2026-10-22 — Step 2 can't pass its check. With every port prefixed by `127.0.0.1:`, `bash tests/0001-loopback-ports.sh config` (frozen at step 1) still reports `KO` for 8 of the 9 ports, although it prints `host_ip: 127.0.0.1` for each. — Why: this workstation's `jq` is Windows' native `jq.exe`, which ends every line with `\r\n` unless given `-b`. Git Bash's command substitution strips only the last `\r`, so `test "$host_ip" = 127.0.0.1` compares `127.0.0.1\r` (only 443, the last line, passes). Step 1's run showed `KO` for the expected reason (`host_ip: none`) and hid it. Diagnosis, with `jq` shimmed to `jq -b` (an exported function, not a change to the test): the part passes on the changed `compose.yml` (`every check passed`, exit 0) and reports 9 `KO` on the original one. No other part reads `jq` (`docker` writes `\n`). — Impact: the fix belongs in the frozen reproducing test, which is AC-1's proof: `| tr -d '\r'` after its `jq` (portable: Ubuntu 22.04's jq 1.6 has no `-b`), or a `jq` wrapper in `tests/lib/` that 0003–0008, which read `jq` as well, would reuse. Implementation stopped after step 1, awaiting the engineer's decision. Step 2's `compose.yml` change is not committed.
- 2026-10-22 — Decision on the deviation above: fix the harness, not the frozen test. Approved by the approver for the grouped pass. The frozen test is unchanged (blob `281dfb3`, as in `b6fa530`). `tests/lib/assert.sh` gains a CR-stripping `jq` (`command jq "$@" | tr -d '\r'`, jq's exit status kept; since the review of 2026-10-22, `sed 's/\r$//'`, which keeps a `\r` inside a value), used by every later c4-infra test that sources it. — Why: the frozen test already sources `tests/lib/assert.sh`. — Impact: no new file (`tests/lib/assert.sh` is in *Files*). Proof that nothing is weakened: on the original `compose.yml`, `bash tests/0001-loopback-ports.sh config` still reports `KO` for each of the 9 ports (`host_ip: none`, `9 check(s) failed`, exit 1). Implementation resumes at step 2.
- 2026-10-22 — Step 6: Faito's REST API doesn't start with `./mvnw -pl faito-api spring-boot:run`. After an incremental build: `Unresolved compilation problem: RoleRepresentationMapper cannot be resolved to a type`. After a clean build: `UserRepresentationMapper … could not be found`. — Why: VS Code's Java extension rewrites `backend/faito-api/target/classes` once Maven is done, with the Eclipse compiler and without MapStruct (`classes/` modified at 06:27:12, Maven's jar at 06:26:59; `UserRepresentationMapperImpl.class` gone from `classes/`, present in the jar). — Instead, the API runs from the jar Maven built: `java -jar target/faito-api-0.0.1-SNAPSHOT.jar` in `backend/faito-api`, `.env` exported. The plan's note on jars concerns the gateway only, which runs with `spring-boot:run` as planned. — Impact: none on files or proofs.
- 2026-10-22 — Review round 1 (sdlc-verify): `.gitignore` also ignores `.claude/settings.local.json`. — Why: `.claude/*.local` doesn't match it, and the plan's line means "any other local state, never committed". On this workstation only the user's global git ignore covered it. — Impact: one more line in a listed file, no proof change.
