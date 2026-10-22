#!/usr/bin/env bash
# Trusts the local CA in a JDK: imports c4-infra's certs/ca.crt, the CA's certificate only (its private
# key stays in ~/.ssh), into that JDK's trust store, under the alias host.docker.internal.
#
#   bash certs/trust-ca-in-jdk.sh [<JDK home>]   (default: $JAVA_HOME), once per JDK running the projects
#
# What the alias holds decides: nothing → ca.crt imported; ca.crt → nothing done ("already trusted");
# another certificate (a former CA) or a private key (the former advice imported the CA's keystore
# whole) → deleted, then ca.crt imported. The other aliases are left as they are.
#
# The trust store's password is read from CACERTS_PASSWORD (changeit by default), never from a command
# line. CACERTS=<file> addresses another trust store than the JDK's own (the tests).
set -euo pipefail

ALIAS=host.docker.internal
CA=$(cd "$(dirname "$0")" && pwd)/ca.crt

jdk=${1:-${JAVA_HOME:-}}
if [ -z "$jdk" ]; then
  echo "Usage: $0 <JDK home> (or JAVA_HOME set)" >&2
  exit 2
fi
keytool=$jdk/bin/keytool
if [ ! -x "$keytool" ]; then
  echo "No bin/keytool in $jdk: not a JDK home" >&2
  exit 1
fi
if [ ! -f "$CA" ]; then
  echo "No $CA: run certs/make-certs.sh (or up.sh) first" >&2
  exit 1
fi

export CACERTS_PASSWORD=${CACERTS_PASSWORD:-changeit}
if [ -n "${CACERTS:-}" ]; then
  store=(-keystore "$CACERTS")
  where=$CACERTS
else
  store=(-cacerts)
  where="$jdk's cacerts"
fi

# keytool in English (its output is read here), without the \r of Windows
kt() {
  "$keytool" -J-Duser.language=en "$@" | tr -d '\r'
}
first_sha256() {
  awk '/^[[:space:]]*SHA256:/ && !fp { fp = $2 } END { print fp }'
}

fingerprint=$(kt -printcert -file "$CA" | first_sha256)
if [ -z "$fingerprint" ]; then
  echo "Can't read the fingerprint of $CA" >&2
  exit 1
fi

if listing=$(kt -list -v -alias "$ALIAS" "${store[@]}" -storepass:env CACERTS_PASSWORD 2>&1); then
  type=$(awk '/^Entry type:/ { print $3 }' <<< "$listing")
elif grep -qF "Alias <$ALIAS> does not exist" <<< "$listing"; then
  type=
else
  printf '%s\n' "$listing" | head -n 3 >&2
  echo "Can't read $where (its password: CACERTS_PASSWORD, changeit by default)" >&2
  exit 1
fi

change() { # <keytool command…>: on the trust store, or says why it can't
  local output
  if ! output=$(kt "$@" "${store[@]}" -storepass:env CACERTS_PASSWORD 2>&1); then
    printf '%s\n' "$output" | head -n 3 >&2
    echo "Can't change $where: a JDK installed for every user (under C:\\Program Files, /usr/lib/jvm)" \
      "needs this script run from an administrator's terminal (sudo on Linux)" >&2
    exit 1
  fi
}

case "$type" in
  '')
    change -importcert -noprompt -alias "$ALIAS" -file "$CA"
    echo "$ALIAS: the local CA's certificate imported into $where"
    ;;
  trustedCertEntry)
    current=$(first_sha256 <<< "$listing")
    if [ "$current" = "$fingerprint" ]; then
      echo "$ALIAS: already trusted in $where (the local CA's certificate), nothing changed"
      exit 0
    fi
    change -delete -alias "$ALIAS"
    change -importcert -noprompt -alias "$ALIAS" -file "$CA"
    echo "$ALIAS: another certificate (SHA-256 $current) replaced by the local CA's in $where"
    ;;
  PrivateKeyEntry)
    change -delete -alias "$ALIAS"
    change -importcert -noprompt -alias "$ALIAS" -file "$CA"
    echo "$ALIAS: a private key (the former advice imported the CA's whole keystore) deleted from $where," \
      "the local CA's certificate imported instead"
    ;;
  *)
    change -delete -alias "$ALIAS"
    change -importcert -noprompt -alias "$ALIAS" -file "$CA"
    echo "$ALIAS: a $type replaced by the local CA's certificate in $where"
    ;;
esac
