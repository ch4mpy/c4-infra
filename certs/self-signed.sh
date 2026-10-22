#!/usr/bin/env bash

CN=$1
if [ -z "${CN}" ]; then
  echo "The certificate CN is expected as argument. You might use \"ci-self-signed.sh \$HOSTNAME\" or \"ci-self-signed.sh \`hostname\` depending on your OS\""
  exit 1
fi

C="PF"
ST="Tahiti"
L="Papeete"
O="Jerome Wacongne"
EMAIL_ADDRESS="ch4mp@c4-soft.com"

SSL_PASSWORD=$2
if [ -z "${SSL_PASSWORD}" ]; then
  SSL_PASSWORD=$SERVER_SSL_KEY_PASSWORD
fi
if [ -z "${SSL_PASSWORD}" ]; then
  SSL_PASSWORD=secret
fi
if [ -z "${JAVA_HOME}" ]; then
  JAVA_HOME=$(which java | sed 's/\/bin\/java//')
  export JAVA_HOME
fi

CERTIF_DIR=$3
if [ -z "${CERTIF_DIR}" ]; then
  echo "Defaulting CERTIF_DIR to ~/.ssh"
  CERTIF_DIR=`echo ~/.ssh`
fi

# Create templated config
rm ${CERTIF_DIR}/${CN}.config
echo creating ${CERTIF_DIR}/${CN}.config
echo -e "[req]\n\
default_bits       = 2048\n\
default_md         = sha256\n\
prompt             = no\n\
default_keyfile    = ${CN}.key\n\
encrypt_key        = no\n\
\n\
distinguished_name = dn\n\
\n\
req_extensions     = v3_req\n\
x509_extensions    = v3_req\n\
\n\
[dn]\n\
C            = ${C}\n\
ST           = ${ST}\n\
L            = ${L}\n\
O            = ${O}\n\
emailAddress = ${EMAIL_ADDRESS}\n\
CN           = ${CN}\n\
\n\
[v3_req]\n\
subjectAltName   = critical, @alt_names\n\
basicConstraints = critical, CA:TRUE\n\
keyUsage         = critical, digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment, keyAgreement, keyCertSign, cRLSign\n\
extendedKeyUsage = critical, serverAuth, clientAuth\n\
\n\
[alt_names]\n\
DNS.1 = ${CN}\n\
DNS.2 = localhost\n\
DNS.3 = host.docker.internal\n\
IP.1 = 127.0.0.1\n\
IP.2 = 10.0.2.2\n\
" > ${CERTIF_DIR}/${CN}.config

echo ""
if [ -f ${CERTIF_DIR}/${CN}_req.pem ]; then
  echo "${CERTIF_DIR}/${CN}_req.pem already exists, doing nothing"
else
  echo "Generating certificate request: ${CERTIF_DIR}/${CN}_req.pem"
  openssl req -config ${CERTIF_DIR}/${CN}.config -new -keyout ${CERTIF_DIR}/${CN}.key -passout pass:"${SSL_PASSWORD}" -out ${CERTIF_DIR}/${CN}_req.pem -reqexts v3_req
fi

echo ""
if [ -f ${CERTIF_DIR}/${CN}.crt ]; then
  echo "${CERTIF_DIR}/${CN}.crt already exists, doing nothing"
else
  echo "Signing certificate: ${CERTIF_DIR}/${CN}.crt"
  openssl x509 -req -days 3650 -extfile ${CERTIF_DIR}/${CN}.config -in ${CERTIF_DIR}/${CN}_req.pem -extensions v3_req -signkey ${CERTIF_DIR}/${CN}.key -passin pass:${SSL_PASSWORD} -out ${CERTIF_DIR}/${CN}.crt
fi
 
echo ""
if [ -f ${CERTIF_DIR}/${CN}.p12 ]; then
  echo "${CERTIF_DIR}/${CN}.p12 already exists, doing nothing"
else
  echo "Creating PKCS12 keystore: ${CERTIF_DIR}/${CN}.p12"
  openssl pkcs12 -export -in ${CERTIF_DIR}/${CN}.crt -inkey ${CERTIF_DIR}/${CN}.key -passin pass:"${SSL_PASSWORD}" -name "${CN}" -out ${CERTIF_DIR}/${CN}.p12 -passout pass:"${SSL_PASSWORD}"
fi

echo ""
if [ -f ${CERTIF_DIR}/${CN}.jks ]; then
  echo "${CERTIF_DIR}/${CN}.jks already exists, doing nothing"
else
  echo "Creating JKS keystore: ${CERTIF_DIR}/${CN}.jks"
  echo "${JAVA_HOME}/bin/keytool" -importkeystore -srckeystore ${CERTIF_DIR}/${CN}.p12 -srckeypass "${SSL_PASSWORD}" -srcstorepass "${SSL_PASSWORD}" -srcstoretype pkcs12 -srcalias "${CN}" -destkeystore ${CERTIF_DIR}/${CN}.jks -deststoretype PKCS12 -destkeypass "${SSL_PASSWORD}" -deststorepass "${SSL_PASSWORD}" -destalias "${CN}"
  "${JAVA_HOME}/bin/keytool" -importkeystore -srckeystore ${CERTIF_DIR}/${CN}.p12 -srckeypass "${SSL_PASSWORD}" -srcstorepass "${SSL_PASSWORD}" -srcstoretype pkcs12 -srcalias "${CN}" -destkeystore ${CERTIF_DIR}/${CN}.jks -deststoretype PKCS12 -destkeypass "${SSL_PASSWORD}" -deststorepass "${SSL_PASSWORD}" -destalias "${CN}"
fi

echo ""
if [ -f ${CERTIF_DIR}/${CN}.password.txt ]; then
  echo "${CERTIF_DIR}/${CN}.password.txt already exists, doing nothing"
else
  echo "Saving the SSL password to: ${CERTIF_DIR}/${CN}.password.txt"
  echo "${SSL_PASSWORD}" > ${CERTIF_DIR}/${CN}.password.txt
fi
