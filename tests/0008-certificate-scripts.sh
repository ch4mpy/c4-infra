#!/usr/bin/env bash
# 0008: c4-infra's certificate scripts put the local CA's private key nowhere but its own directory
# (~/.ssh), and no password in their output or on a command line (the intent's success criterion).
#
#   bash tests/0008-certificate-scripts.sh [advice|passwords]   (both by default)
#
#   advice      make-certs.sh, creating a CA, advises a c4-infra script for the JDKs; run on copies of a
#               JDK's cacerts (a fresh one, one holding the CA's PrivateKeyEntry as the former advice
#               left it, one holding another certificate under the alias), that advice leaves the CA's
#               certificate as the trustedCertEntry host.docker.internal and no private key of the CA;
#               a second run changes nothing
#   passwords   neither make-certs.sh nor self-signed.sh prints a password or puts one on a command line
#               (every bash, openssl and keytool they run logged by tests/lib/argv-log.sh's wrappers);
#               self-signed.sh still writes its files and refuses a password argument; the Mailpit hash
#               command of docs/demo-setup.md (step 5) reads its password on stdin
#
# Everything runs in a temporary directory: a copy of certs/*.sh with its own .env, a throwaway CA
# (CA_DIR), copies of a JDK's cacerts. Neither ~/.ssh, the repository's certs/ nor a JDK is touched.
# The JDK is JAVA_HOME's, else the first of ~/.sdkman/candidates/java/; the test's own keytool calls
# run it directly, outside the wrappers, with the passwords in their environment (the :env forms).
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/argv-log.sh

case "${1:-}" in
  '') parts=(advice passwords) ;;
  advice | passwords) parts=("$1") ;;
  *)
    echo "Usage: $0 [advice|passwords]" >&2
    exit 2
    ;;
esac

ALIAS=host.docker.internal

REAL_JAVA_HOME=${JAVA_HOME:-}
if [ -z "$REAL_JAVA_HOME" ]; then
  for jdk in "$HOME"/.sdkman/candidates/java/*/; do
    if [ -x "$jdk/bin/keytool" ]; then
      REAL_JAVA_HOME=${jdk%/}
      break
    fi
  done
fi
REAL_KEYTOOL=$REAL_JAVA_HOME/bin/keytool
check "a JDK to test with (JAVA_HOME, else ~/.sdkman/candidates/java/*): ${REAL_JAVA_HOME:-none}" \
  test -n "$REAL_JAVA_HOME" -a -x "$REAL_KEYTOOL" -a -f "$REAL_JAVA_HOME/lib/security/cacerts"
[ "$failures" -eq 0 ] || finish

# the throwaway CA's key and passwords: private, and removed whatever happens
umask 077
tmp=$(mktemp -d)
chmod 700 "$tmp"
trap 'rm -rf "$tmp"' EXIT
export CACERTS_PASSWORD=changeit

kt() { # the JDK's keytool, in English, without the \r of Windows (pipefail keeps its status)
  "$REAL_KEYTOOL" -J-Duser.language=en "$@" | tr -d '\r'
}

# $tmp/<part>/: a copy of the repository's certificate scripts with the .env make-certs.sh reads, the
# wrappers of bash and openssl (bin/) and of keytool (jdk/); the part's log is $tmp/<part>.argv
setup() { # <part>
  local dir=$tmp/$1
  mkdir -p "$dir/repo/certs"
  cp certs/*.sh "$dir/repo/certs/"
  printf 'INFRA_HOST=%s\nAPPS_DOMAIN=dev.localhost\n' "$ALIAS" > "$dir/repo/.env"
  argv_log_path "$dir/bin" bash openssl
  JAVA_HOME=$REAL_JAVA_HOME argv_log_java_home "$dir/jdk"
  export ARGV_LOG=$tmp/$1.argv
  : > "$ARGV_LOG"
}

under_test() { # <part> <command…>: with that part's wrappers first on PATH and as JAVA_HOME
  local dir=$tmp/$1
  shift
  PATH="$dir/bin:$PATH" JAVA_HOME="$dir/jdk" "$@" < /dev/null
}

make_certs() { # <part>: make-certs.sh of the part's copy, creating its CA in $tmp/<part>/ca
  CA_DIR=$tmp/$1/ca under_test "$1" bash "$tmp/$1/repo/certs/make-certs.sh" > "$tmp/$1/make-certs.out" 2>&1
}

created_ca() { # <part> <status>
  local dir=$tmp/$1
  [ "$2" -eq 0 ] && [ -f "$dir/ca/$ALIAS.crt" ] && [ -s "$dir/ca/$ALIAS.password.txt" ] \
    && [ -f "$dir/repo/certs/ca.crt" ] \
    || { echo "exit $2:"; tail -n 20 "$dir/make-certs.out"; return 1; }
}

lacks_password() { # <password file> <file>: the password is nowhere in the file (shown masked if it is)
  local password line found=false
  password=$(< "$1")
  [ -n "$password" ] || { echo "no password in $1"; return 1; }
  while IFS= read -r line; do
    if [[ $line == *"$password"* ]]; then
      $found || echo "the password is in $(basename "$2"):"
      found=true
      printf '%s\n' "${line//"$password"/<password>}"
    fi
  done < "$2"
  ! $found
}

lacks() { # <fixed string> <text>
  [[ $2 != *"$1"* ]] || { printf '%s\n' "$2"; return 1; }
}

absent_from() { # <fixed string> <file>: prints the lines holding it, if any
  ! grep -nF -- "$1" "$2"
}

logged() { # <log> <extended regex>: a logged command line matches
  grep -qE -- "$2" "$1" || { echo "no command line matching $2 in $(basename "$1"):"; cat "$1"; return 1; }
}

# --- advice ---------------------------------------------------------------------------------------

alias_entry() { # <store>: "<entry type> <SHA-256 of its first certificate>" for the alias, or nothing
  kt -list -v -keystore "$1" -storepass:env CACERTS_PASSWORD -alias "$ALIAS" 2> /dev/null \
    | awk '/^Entry type:/ { type = $3 } /^[[:space:]]*SHA256:/ && !fp { fp = $2 } END { if (type) print type, fp }'
}

trusts_the_ca() { # <store>
  local entry
  entry=$(alias_entry "$1")
  [ "$entry" = "trustedCertEntry $ca_fingerprint" ] \
    || { echo "$ALIAS: ${entry:-absent}; expected trustedCertEntry $ca_fingerprint"; return 1; }
}

holds_no_ca_key() { # <store>: no PrivateKeyEntry whose chain holds the CA's certificate
  local listing keys
  listing=$(kt -list -v -keystore "$1" -storepass:env CACERTS_PASSWORD 2> /dev/null) \
    || { echo "the trust store doesn't open:"; tail -n 3 <<< "$listing"; return 1; }
  keys=$(awk -v fp="$ca_fingerprint" '/^Alias name:/ { name = $3 } /^Entry type:/ { type = $3 }
    /^[[:space:]]*SHA256:/ && type == "PrivateKeyEntry" && $2 == fp { print name }' <<< "$listing")
  [ -z "$keys" ] || { echo "the CA's private key, under: $keys"; return 1; }
}

ran() { # <status> <output file>
  [ "$1" -eq 0 ] || { echo "exit $1:"; tail -n 20 "$2"; return 1; }
}

advice() {
  local dir=$tmp/advice repo=$tmp/advice/repo status line advised words script store label
  setup advice
  make_certs advice
  status=$?
  check "advice: make-certs.sh creates a throwaway CA" created_ca advice "$status"

  line=$(grep -m1 '^  - .*JDK' "$dir/make-certs.out")
  advised=${line#*: }
  echo "# advised for the JDKs: ${advised:-nothing}"
  read -ra words <<< "$advised"
  script=${words[1]:-}
  advises_trust_script() {
    [ "${words[0]:-}" = bash ] && [ -f "$repo/certs/trust-ca-in-jdk.sh" ] \
      && [ "$script" -ef "$repo/certs/trust-ca-in-jdk.sh" ] \
      || { echo "advised: ${advised:-nothing}"; return 1; }
  }
  check "the advice runs c4-infra's own certs/trust-ca-in-jdk.sh" advises_trust_script
  check "the advice names no .jks" lacks .jks "$advised"
  check "the advice names no project's script (<project>)" lacks '<project>' "$advised"
  check "the advice takes no password argument (<password>)" lacks '<password>' "$advised"
  printf '%s\n' "$advised" > "$dir/advised"
  check "the advice holds not the CA's password" lacks_password "$dir/ca/$ALIAS.password.txt" "$dir/advised"

  # only `bash <c4-infra>/certs/trust-ca-in-jdk.sh <JDK home>` runs: the former advice's <…> would be
  # redirections
  runnable() {
    advises_trust_script > /dev/null && [ "${#words[@]}" -eq 4 ] && [ "${words[2]} ${words[3]}" = '<JDK home>' ] \
      || { echo "not run: the advice isn't \`bash <c4-infra>/certs/trust-ca-in-jdk.sh <JDK home>\`"; return 1; }
  }
  check "the advice is \`bash <c4-infra>/certs/trust-ca-in-jdk.sh <JDK home>\`" runnable
  runnable > /dev/null || return 0

  ca_fingerprint=$(openssl x509 -in "$repo/certs/ca.crt" -noout -fingerprint -sha256 | tr -d '\r' | sed 's/^.*=//')
  # three copies of the JDK's trust store, without the alias (a JDK of this workstation may trust
  # its own CA under it), then each in the state it is tested from
  for store in fresh private-key other; do
    cp "$REAL_JAVA_HOME/lib/security/cacerts" "$dir/$store.cacerts"
    kt -delete -keystore "$dir/$store.cacerts" -storepass:env CACERTS_PASSWORD -alias "$ALIAS" > /dev/null 2>&1
  done
  # the former advice's state: the CA's keystore imported whole, its private key under the alias
  CA_PASSWORD=$(< "$dir/ca/$ALIAS.password.txt") kt -importkeystore -noprompt \
    -srckeystore "$dir/ca/$ALIAS.p12" -srcstoretype PKCS12 -srcstorepass:env CA_PASSWORD -srcalias "$ALIAS" \
    -destkeystore "$dir/private-key.cacerts" -deststorepass:env CACERTS_PASSWORD -destalias "$ALIAS" \
    > "$dir/seed.out" 2>&1
  # another certificate under the alias (a former CA, or a project's import of another certificate)
  MSYS2_ARG_CONV_EXCL="/CN=" openssl req -x509 -newkey rsa:2048 -nodes -keyout "$dir/other.key" \
    -subj "/CN=another CA" -days 1 -out "$dir/other.crt" > /dev/null 2>&1
  kt -importcert -noprompt -keystore "$dir/other.cacerts" -storepass:env CACERTS_PASSWORD -alias "$ALIAS" \
    -file "$dir/other.crt" >> "$dir/seed.out" 2>&1
  starts_as() { # <store> <expected entry type> [not-the-CA]
    local entry
    entry=$(alias_entry "$1")
    [ "${entry%% *}" = "$2" ] && { [ -z "${3:-}" ] || [ "${entry#* }" != "$ca_fingerprint" ]; } \
      || { echo "$ALIAS: ${entry:-absent}"; cat "$dir/seed.out"; return 1; }
  }
  check "seeded: the fresh copy has no $ALIAS" test -z "$(alias_entry "$dir/fresh.cacerts")"
  check "seeded: a copy holds the CA's PrivateKeyEntry under $ALIAS" starts_as "$dir/private-key.cacerts" PrivateKeyEntry
  check "seeded: a copy holds another certificate under $ALIAS" starts_as "$dir/other.cacerts" trustedCertEntry not-the-CA

  for store in fresh private-key other; do
    case "$store" in
      fresh) label="a fresh cacerts" ;;
      private-key) label="a cacerts holding the CA's private key (the former advice)" ;;
      other) label="a cacerts holding another certificate under $ALIAS" ;;
    esac
    CACERTS=$dir/$store.cacerts under_test advice bash "$script" "$dir/jdk" > "$dir/$store.out" 2>&1
    status=$?
    check "$label: the advice exits 0" ran "$status" "$dir/$store.out"
    check "$label: $ALIAS is the CA's certificate, a trustedCertEntry" trusts_the_ca "$dir/$store.cacerts"
    check "$label: no private key of the CA" holds_no_ca_key "$dir/$store.cacerts"
  done

  local before after
  before=$(cksum < "$dir/fresh.cacerts")
  CACERTS=$dir/fresh.cacerts under_test advice bash "$script" "$dir/jdk" > "$dir/again.out" 2>&1
  status=$?
  after=$(cksum < "$dir/fresh.cacerts")
  check "a second run exits 0" ran "$status" "$dir/again.out"
  check "a second run says the CA is already trusted" grep -qi 'already trusted' "$dir/again.out"
  check "a second run leaves the trust store as it was" test "$before" = "$after"
  printf '%s\n' "$CACERTS_PASSWORD" > "$dir/cacerts.password"
  check "the trust store's password is on no command line of the advice" lacks_password "$dir/cacerts.password" "$ARGV_LOG"
}

# --- passwords ------------------------------------------------------------------------------------

passwords() {
  local dir=$tmp/passwords repo=$tmp/passwords/repo status
  setup passwords
  make_certs passwords
  status=$?
  check "passwords: make-certs.sh creates a throwaway CA" created_ca passwords "$status"
  check "the wrappers logged make-certs.sh's call of self-signed.sh" logged "$ARGV_LOG" '^bash .*self-signed\.sh'
  check "the CA's password is not in make-certs.sh's output" \
    lacks_password "$dir/ca/$ALIAS.password.txt" "$dir/make-certs.out"
  check "the CA's password is on no command line make-certs.sh ran" \
    lacks_password "$dir/ca/$ALIAS.password.txt" "$ARGV_LOG"

  # self-signed.sh on its own, its password in its environment (echo is a builtin)
  mkdir -p "$dir/out"
  echo "$(openssl rand -hex 16)" > "$dir/probe.password"
  : > "$ARGV_LOG"
  SERVER_SSL_KEY_PASSWORD=$(< "$dir/probe.password") \
    under_test passwords bash "$repo/certs/self-signed.sh" probe.local "" "$dir/out" > "$dir/self-signed.out" 2>&1
  status=$?
  check "self-signed.sh exits 0" ran "$status" "$dir/self-signed.out"
  check "the wrappers logged self-signed.sh's openssl" logged "$ARGV_LOG" '^openssl .*probe\.local'
  check "the wrappers logged self-signed.sh's keytool" logged "$ARGV_LOG" '^keytool .*probe\.local'
  check "its password is not in self-signed.sh's output" lacks_password "$dir/probe.password" "$dir/self-signed.out"
  check "its password is on no command line self-signed.sh ran" lacks_password "$dir/probe.password" "$ARGV_LOG"
  local extension
  for extension in crt key p12 jks; do
    check "self-signed.sh writes probe.local.$extension" test -s "$dir/out/probe.local.$extension"
  done
  opens() {
    local listing
    listing=$(PROBE_PASSWORD=$(< "$dir/probe.password") \
      kt -list -keystore "$dir/out/probe.local.jks" -storepass:env PROBE_PASSWORD) \
      && grep -q '^probe\.local,' <<< "$listing" || { printf '%s\n' "$listing"; return 1; }
  }
  check "probe.local.jks opens with that password and holds probe.local" opens

  # a dummy value, not a secret: the argument a caller must no longer pass
  mkdir -p "$dir/refused"
  under_test passwords bash "$repo/certs/self-signed.sh" refused.local not-a-secret "$dir/refused" \
    > "$dir/refused.out" 2>&1
  status=$?
  refused() {
    [ "$status" -ne 0 ] && grep -q SERVER_SSL_KEY_PASSWORD "$dir/refused.out" && [ -z "$(ls -A "$dir/refused")" ] \
      || { echo "exit $status, wrote: $(ls -A "$dir/refused" | tr '\n' ' ')"; tail -n 5 "$dir/refused.out"; return 1; }
  }
  check "self-signed.sh refuses a password argument, saying to export SERVER_SSL_KEY_PASSWORD" refused

  # docs/demo-setup.md, step 5: the Mailpit UI password's bcrypt hash, the password on caddy's stdin
  check "docs/demo-setup.md gives caddy hash-password no --plaintext" absent_from --plaintext docs/demo-setup.md
  awk '/^## 5\./ { s = 1; next } /^## / { s = 0 } s && /^```bash/ { b = 1; next } s && b && /^```/ { b = 0 } s && b' \
    docs/demo-setup.md > "$dir/hash.sh"
  check "docs/demo-setup.md's step 5 has a command running caddy hash-password" grep -q 'caddy hash-password' "$dir/hash.sh"
  argv_log_path "$dir/docker-bin" docker
  echo "$(openssl rand -hex 16)" > "$dir/mailpit.password"
  : > "$ARGV_LOG"
  PATH="$dir/docker-bin:$PATH" bash "$dir/hash.sh" < "$dir/mailpit.password" > "$dir/hash.out" 2>&1
  status=$?
  hashed() {
    [ "$status" -eq 0 ] && tr -d '\r' < "$dir/hash.out" | grep -qE '^\$2[aby]\$[0-9]{2}\$' \
      || { echo "exit $status:"; tail -n 5 "$dir/hash.out"; return 1; }
  }
  check "that command prints a bcrypt hash of the password typed" hashed
  check "the wrapper logged its docker run" logged "$ARGV_LOG" '^docker run .*caddy hash-password'
  check "the Mailpit password is not in that command's output" lacks_password "$dir/mailpit.password" "$dir/hash.out"
  check "the Mailpit password is on no command line of it" lacks_password "$dir/mailpit.password" "$ARGV_LOG"
}

for part in "${parts[@]}"; do
  "$part"
done
finish
