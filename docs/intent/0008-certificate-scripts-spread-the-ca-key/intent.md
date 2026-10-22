# Intent: c4-infra's certificate scripts spread the local CA's private key and its password

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: bug
- Source: conversation (coherence review of the plans, 2026-10-22; follow-up of Faito 0022 and skills 0016)
- Spec needed: no
- Status: accepted
- Opened: 2026-10-22
- Decided: 2026-10-22
- Supersedes: —

## Problem

- `certs/make-certs.sh:30` tells developers to trust the local CA in each JDK with `bash <project>/certs/add-to-jre-cacerts.sh $CA_DIR/$CA_NAME.jks <password> $CA_NAME`. That script imports the whole keystore (`keytool -importkeystore`), so the JDK's `cacerts` receives the CA's private key as a `PrivateKeyEntry`. On 2026-10-22, five JDKs of the workstation held it, readable by anything that reads `cacerts` with its well-known default password; they were cleaned by hand the same day.
- After Faito 0022 and skills 0016, the projects' `add-to-jre-cacerts.sh` takes a certificate and an alias, and the generated projects have no `certs/` any more: the advice points to a script that is gone, or that takes other arguments.
- `certs/self-signed.sh:99-100` prints the `keytool` command with the keystore's password, then runs it with the password on its command line, readable in the terminal's scrollback and the process list.

## Proposed outcome

c4-infra's certificate scripts never put the CA's private key anywhere but `~/.ssh`, and never print or pass a password on a command line. Success criterion: following `make-certs.sh`'s advice on a JDK leaves a `trustedCertEntry` for the CA (its certificate only) in its `cacerts`; `self-signed.sh`'s output and its processes' command lines hold no password.

## Affected users and systems

- Developer (their workstation and its JDKs).
- Certificates (`certs/make-certs.sh`, `certs/self-signed.sh`).

## Constraints

- The local CA stays the only trust to install (README: one certificate, no new trust).
- No password on a command line (`CLAUDE.md`).

## Open questions

- None.
