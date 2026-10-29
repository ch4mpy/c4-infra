# Spec: The stand-in demo host can't serve an application over HTTPS

- Intent: [0035](intent.md)
- Status: draft
- Version: 1
- Risk: standard (no risk rule applies: the real host's configuration, certificates and secrets don't change, IV-01; the local authority is a test's throwaway, trusted by the test's client alone, its keys kept in the stand-in, IV-02; it would be high if the change reached a file the real host receives)
- Policies applied: none yet; standing constraints: README design (a Let's Encrypt certificate per site on the demo host), CLAUDE.md (bash and Git Bash, no password on a command line, a script comes with its test and its `# covers:`), the library's contract with the skills' tests (their 0095 PA-06 A: sourced from a c4-infra checkout)
- Approved: —

## Summary

The stand-in demo host's Caddy serves the shared host and every registered application's site over HTTPS, with certificates from a local authority (PA-01), always or when a test asks (PA-02). A test gets that authority's root certificate from `tests/lib/stand-in-host.sh` and trusts it alone in its client (PA-03). For the Developer: c4-infra's tests, and the skills' 0095 and 0099, prove a page, then a login, through the stand-in's proxy over HTTPS. The real demo host and what it receives don't change.

## Requirements

- **RQ-01:** The stand-in's Caddy serves over HTTPS, with a certificate for the site's name, its shared host (`INFRA_HOST`) and each site `register-app.sh` installs, a site registered after the stack started included, through every reload the host's scripts make (`register-app.sh`, `demo/deploy.sh`). (intent: outcome; problem, the login through the shared proxy)
- **RQ-02:** Those certificates come from a local authority (PA-01); nothing reaches Let's Encrypt or another public authority (`compose.no-acme.yml`'s cut stays). (intent: outcome; constraint)
- **RQ-03:** Once the stack is deployed, the library gives a test the authority's root certificate (PEM, no key) for its client's only trust anchor, and fails, saying why, when the stack or the authority isn't there; PA-03 decides whether it also gives a request function. (intent: outcome, "trusts in its own client")
- **RQ-04:** HTTPS is always on, or on when a test asks (PA-02); either way the existing stand-in tests pass with their checks unchanged: the stack's directory holds what the deployment sends, `.env` and `compose.no-acme.yml`, `COMPOSE_FILE` as today (`0003-demo-deploy.stand-in.sh:39-51`), the redirect from HTTP still `308`. (intent: success criterion)
- **RQ-05:** The library's header says how to get the root, how a client reaches a site by its name (resolved to the stand-in's Caddy from inside the stand-in, which publishes no port), and that nothing else trusts that root; a skills test that sources the library needs nothing more. (intent: affected users, the skills' tests)
- **RQ-06:** It works under Git Bash with Docker Desktop and under bash on Ubuntu. (intent: constraint)
- **IV-01:** The real demo host is unchanged: the files of `demo/deploy-files.txt`, `demo/write-env.sh` and `.github/workflows/` stay as they are, or Caddy adapts the demo configuration (`INFRA_ENV=demo`) to the same JSON. (intent: constraint)
- **IV-02:** The authority's private keys stay in the stand-in (PA-01 B: and in the test's temporary directory, removed at its end): never in the repository, another file of the workstation, a trust store (the workstation's, the stand-in's or its containers'), nor on the real host. (intent: constraint)

## Out of scope

- Trust in the applications' containers: the skills' JVMs reach Keycloak at `http://keycloak:8080` (their 0099 PA-04 B); a test may hand them the root itself.
- A login, Keycloak's `sslRequired`, the session cookie: the skills' 0099 AC-01 proves them on this.
- The real host's issuance from Let's Encrypt (PA-01 C aside); dev's local CA (`certs/`), trusted by the workstation (`certs/make-certs.sh:4-5`, intent 0008); turning the existing checks into HTTPS ones.

## Design

### Current behaviour

- Every site imports `site`, then `env-tls` (`caddy/Caddyfile:42-44`, `routes.sh:268`), empty on the demo host (`caddy/env/demo.caddy:5`): Caddy's automatic HTTPS from Let's Encrypt.
- The stand-in adds `compose.no-acme.yml` to `COMPOSE_FILE` (`tests/lib/stand-in-host.sh:151-153`), which points Caddy's DNS at no resolver: Caddy gets no certificate, an HTTPS request none to verify (inferred, no stand-in run at draft). The tests request the sites from inside the stand-in, `http://127.0.0.1` with a `Host` header, and check only the `308` (`0003-demo-deploy.stand-in.sh:105-106`, `:115-116`; `0013-mcp.stand-in.sh:93`); 0013 leaves HTTPS to a throwaway Caddy (`:16-17`).
- `tests/0003-demo-edge.sh:66` and `tests/0015-headers.sh:70` wrap the demo configuration in `{ local_certs; skip_install_trust }` and `import /etc/caddy/Caddyfile`, started from `/test/Caddyfile`, their client `curl -k` (`0003-demo-edge.sh:77`). On the stand-in such a wrapper would be dropped at the first reload: `register-app.sh:511-512` and `demo/deploy.sh:57` reload from `/etc/caddy/Caddyfile`.
- The stand-in publishes no port (`tests/lib/stand-in-host.sh:79-80`); `stand_in_up` removes an earlier run's volumes (`:91-94`), `stand_in_down` keeps its Docker volume. 0006 and 0009 rewrite `.env` and re-add `compose.no-acme.yml` themselves (`0006-bootstrap-admin-replaced.stand-in.sh:222`, `0009-master-realm.stand-in.sh:282`). No stand-in check needs the missing certificate: the isolation tests probe `:443` with `nc -z` (`0007-isolation.stand-in.sh:128-131`).

### Behaviour per persona

- **Developer** (c4-infra's tests; the skills' 0095 and 0099 through `C4_INFRA_SRC`): deploys the stack on the stand-in as today (PA-02 A: asking for HTTPS), registers an application, takes the root, and requests `https://<site>/…` from inside the stand-in, trusting only that root.
- **Demo operator, Demo visitor**: nothing changes (IV-01).

### API and contracts

- The root: a function, e.g. `stand_in_ca_cert`, prints its PEM on stdout; the caller writes it where its client runs (in the stand-in with `stand_in_exec -i`, or its temporary directory); exit 1 and a message when the stack or the authority is missing.
- PA-02 A: a switch read before the stack is deployed (`stand_in_env`, `stand_in_accounts`), e.g. `STAND_IN_HTTPS=1`, as `STAND_IN_FRESH`.
- PA-03 B: `stand_in_https <host> <path> [curl option…]`, run in the stand-in: the name resolved to its Caddy on `:443`, the root as the only trust anchor (no `-k`, no system store), the caller's options passed through.

### User interface, Data

None.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| — | No policy yet. Standing constraints: README design → IV-01; bash and Git Bash → RQ-06, AC-07; a script with its test and its `# covers:` → AC-01's test covers the library and `tests/stand-in-host/`; the library's contract with the skills → RQ-03, RQ-05 |

## Points of attention

### PA-01: Where the certificates come from (intent question 1)

- Issue: the intent offers Caddy's own authority or one the test gives; its constraint keeps the key "in the test's temporary files".
- Options: A) Caddy's local authority (`local_certs`, as `0003-demo-edge.sh:66`), created by the stand-in's Caddy in its data volume; the test reads the root from Caddy / B) an authority the test generates in its `mktemp` directory (`openssl`), its root and key given to the stand-in's Caddy, which issues each site's certificate from it; the root known before the stack starts / C) an ACME test server (Pebble) in the stand-in, Caddy's ACME pointed at it: the real host's issuance path exercised, but one more image in a stand-in whose nested DNS fails now and then (HANDOVER; 0020), and a DNS for its challenges.
- Recommendation: A: no key passes through the test, the workstation or the repository; the pattern two tests use; a certificate per site as Caddy loads it, as on the real host. It reads "the test's temporary files" as the stand-in's throwaway storage, where a run's Keycloak database and passwords already stay until the next `stand_in_up`; B keeps the key in the `mktemp` directory, but a copy goes into the stand-in all the same.
- Decides: PO (the constraint's reading) and tech lead
- Decision: to decide

### PA-02: Always on, or when a test asks (intent question 2)

- Issue: the skills' 0099 PA-07 B asked for "a local-certificates option"; either answer serves it.
- Options: A) when a test asks (a switch): without it, the stand-in is as today; a test that rewrites `.env` asks again / B) always on, within the stand-in's existing override: no file added to the stack's directory, `COMPOSE_FILE` unchanged (RQ-04); every stand-in test runs Caddy with its local authority.
- Recommendation: B: one stand-in configuration instead of two, closer to the real host, no switch to carry through `stand_in_accounts`, the skills' tests and 0006's and 0009's `.env` rewrites; no existing check needs the missing certificate, and a change of `tests/lib/` runs every stand-in test either way. Only 0013's header sentence "The stand-in serves no HTTPS" turns wrong.
- Decides: PO
- Decision: to decide

### PA-03: What the library gives a test's client

- Options: A) the root only; each test builds its client / B) A, plus `stand_in_https`, which c4-infra's test uses and the skills' may.
- Recommendation: B: "trusts only the stand-in's authority" is written once (a curl given a CA file may still read the system's CA directory, not measured on the stand-in's Ubuntu; the name's resolution; the stand-in's curl rather than Windows'), and a skills test passes its own options (0099's login keeps a cookie jar).
- Decides: tech lead
- Decision: to decide

## Acceptance criteria

- **AC-01:** Given the stack deployed on the stand-in (`stand_in_accounts faito`; PA-02 A: asked for) and Faito's fixture (`tests/fixtures/0002/faito/`) registered with `sudo c4-app register --proxy` and started after it, when a client in the stand-in requests `https://faito.c4-soft.com/fr/`, the name resolved to the stand-in's Caddy and RQ-03's root as its only trust anchor, then it gets `200` and `faito.frontend`'s body, under a certificate for `faito.c4-soft.com` issued under that root; the same request trusting the system's store instead fails verification. (RQ-01, RQ-02, RQ-03)
- **AC-02:** Given AC-01's stand-in, when the client requests `https://infra.c4-soft.com/auth/realms/master/.well-known/openid-configuration` the same way, then it gets `200` and the issuer `https://infra.c4-soft.com/auth/realms/master`. (RQ-01)
- **AC-03:** Given AC-01's site, when `demo/deploy.sh` runs again and a second application registers, then both sites answer over HTTPS under the same root. (RQ-01)
- **AC-04:** Given the change, when `bash tests/run.sh --changed --all` runs, then every existing stand-in test passes with its checks unchanged. (RQ-04)
- **AC-05:** Given the change, then `git diff origin/main` shows no change to the files of `demo/deploy-files.txt`, `demo/write-env.sh` or `.github/workflows/`, or Caddy adapts the demo configuration to the same JSON before and after. (IV-01)
- **AC-06:** Given a run of AC-01's test, passed, failed or interrupted, then no private key of the authority is in `git status`, in the stand-in's upload or (PA-01 A) the test's temporary directory, and the root is in no trust store of the stand-in or its containers. (IV-02)
- **AC-07:** Given the library's header, then it states RQ-05's points; AC-01 passes under bash on Ubuntu and under Git Bash with Docker Desktop (the latter run by the Developer, its output in `plan.md`). (RQ-05, RQ-06)

## Intent questions

- How the stand-in gets its certificates (Caddy's internal authority, a test authority the stand-in is given) → PA-01.
- Whether it is an option of the stand-in or always on → PA-02.

## Change log

- v1 — 2026-10-28 — first version (draft; PA-01 to PA-03 to decide)
