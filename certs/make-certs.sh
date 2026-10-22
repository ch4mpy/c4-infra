#!/usr/bin/env bash
# Dev TLS for the shared stack.
#
# The local CA is ~/.ssh/host.docker.internal.crt: the self-signed certificate (CA:TRUE) that the
# projects already use and that is already trusted (Windows certificate store, JDK cacerts). It
# signs the leaf the shared services serve, valid for host.docker.internal, localhost and every
# application host (*.${APPS_DOMAIN}): adding an application needs neither a new certificate nor a
# new trust. Browsers refuse a second-level wildcard such as *.localhost, hence *.dev.localhost.
#
# Writes ./ca.crt (the CA certificate, never its key), ./tls.crt (leaf + CA) and ./tls.key.
set -euo pipefail
# Git Bash would rewrite the -subj argument ("/CN=...") into a Windows path, though not the file paths
export MSYS2_ARG_CONV_EXCL="/CN="
cd "$(dirname "$0")"
source ../.env

CA_DIR=${CA_DIR:-$HOME/.ssh}
CA_NAME=host.docker.internal

if [ ! -f "$CA_DIR/$CA_NAME.crt" ] || [ ! -f "$CA_DIR/$CA_NAME.key" ]; then
  echo "No local CA in $CA_DIR: creating $CA_NAME (same procedure as the projects' certs/self-signed.sh)"
  mkdir -p "$CA_DIR"
  chmod 700 "$CA_DIR"
  password_file="$CA_DIR/$CA_NAME.password.txt"
  [ -f "$password_file" ] || openssl rand -hex 16 > "$password_file"
  bash ./self-signed.sh "$CA_NAME" "$(cat "$password_file")" "$CA_DIR"
  echo
  echo "Trust it once (then restart the browsers):"
  echo "  - Windows: certutil -user -addstore Root \"$CA_DIR/$CA_NAME.crt\""
  echo "  - each JDK running the projects: bash <project>/certs/add-to-jre-cacerts.sh $CA_DIR/$CA_NAME.jks <password> $CA_NAME"
  echo
fi

cp "$CA_DIR/$CA_NAME.crt" ca.crt

# A leaf is (re)issued when missing, expiring within 30 days, not signed by the current CA, or not
# covering exactly the current host names
sans() {
  openssl x509 -in tls.crt -noout -ext subjectAltName | tr -d ' ' | tr ',' '\n' | grep '^DNS:'
}
if [ -f tls.crt ] && openssl x509 -in tls.crt -noout -checkend 2592000 > /dev/null \
  && openssl verify -CAfile ca.crt tls.crt > /dev/null 2>&1 \
  && sans | grep -qxF "DNS:${INFRA_HOST}" && sans | grep -qxF "DNS:*.${APPS_DOMAIN}"; then
  exit 0
fi

echo "Issuing the shared leaf certificate for ${INFRA_HOST}, localhost and *.${APPS_DOMAIN}"
extensions=$(mktemp)
trap 'rm -f "$extensions" tls.csr' EXIT
cat > "$extensions" <<EOF
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = ${INFRA_HOST}
DNS.2 = localhost
DNS.3 = *.${APPS_DOMAIN}
IP.1 = 127.0.0.1
EOF
openssl req -new -newkey rsa:2048 -nodes -keyout tls.key -subj "/CN=${INFRA_HOST}" -out tls.csr
openssl x509 -req -in tls.csr -CA ca.crt -CAkey "$CA_DIR/$CA_NAME.key" -set_serial "0x$(openssl rand -hex 16)" \
  -days 825 -sha256 -extfile "$extensions" -out leaf.crt
cat leaf.crt ca.crt > tls.crt
rm -f leaf.crt
chmod 600 tls.key
