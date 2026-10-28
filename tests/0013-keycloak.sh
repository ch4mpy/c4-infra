#!/usr/bin/env bash
# 0013: what the shared Keycloak offers since 0013, on the dev stack (AC-01, AC-11, AC-12):
#
#   - AC-01: its log names version 26.8.1, exactly two preview features (token-exchange-delegation,
#     parameterized-scopes) and one experimental feature (cimd);
#   - AC-12: a realm's RFC 8414 metadata answers on the issuer host's root, with S256, the iss
#     parameter of the authorization response and client ID metadata documents; an authorization
#     request carrying a resource parameter shows the login page (Keycloak ignores it);
#   - AC-11: the local leaf is valid for an application's MCP origin (faito-mcp.dev.localhost).
#
#   bash tests/0013-keycloak.sh
#
# Needs the dev stack running (up.sh).
#
# covers: up.sh env.sh compose.yml compose.dev.yml caddy/ keycloak/ keycloak-import/ reverse-proxy/
# covers: certs/ registry.sh registry.txt
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/keycloak.sh

BASE=https://host.docker.internal

# AC-01, from the log of Keycloak's last start
log=$(docker logs c4-infra.keycloak 2>&1 | tr -d '\r')
log_says() { # <text>
  grep -qF -- "$1" <<< "$log" || { echo "Keycloak's log lacks: $1"; return 1; }
}
check "AC-01: Keycloak 26.8.1" log_says "Keycloak 26.8.1 on JVM"
check "AC-01: the preview features: token-exchange-delegation, parameterized-scopes" \
  test "$(kc_features Preview "$log")" = "parameterized-scopes:v1,token-exchange-delegation:v1"
check "AC-01: the experimental feature: cimd, alone" test "$(kc_features Experimental "$log")" = "cimd:v1"

# AC-12
metadata=$(kc_curl "$BASE/.well-known/oauth-authorization-server/auth/realms/master")
field() { # <jq filter> <expected>
  local value
  value=$(jq -c "$1" <<< "$metadata")
  [ "$value" = "$2" ] || { echo "$1 is $value, not $2"; return 1; }
}
check "AC-12: the RFC 8414 metadata of realm master, on the issuer host's root" \
  field .issuer "\"$BASE/auth/realms/master\""
check "AC-12: PKCE S256" field '.code_challenge_methods_supported | index("S256") != null' true
check "AC-12: iss in the authorization response" field .authorization_response_iss_parameter_supported true
check "AC-12: client ID metadata documents" field .client_id_metadata_document_supported true
login_page_with_resource() {
  local page
  page=$(kc_curl -G "$BASE/auth/realms/master/protocol/openid-connect/auth" --data-urlencode client_id=security-admin-console \
    --data-urlencode "redirect_uri=$BASE/auth/admin/master/console/" --data-urlencode response_type=code \
    --data-urlencode scope=openid --data-urlencode code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM \
    --data-urlencode code_challenge_method=S256 --data-urlencode "resource=https://faito-mcp.dev.localhost/mcp")
  grep -q 'kc-form-login\|id="username"' <<< "$page" || { echo "not the login page:"; head -c 400 <<< "$page"; return 1; }
}
check "AC-12: an authorization request with resource= shows the login page" login_page_with_resource

# AC-11
check "AC-11: the dev leaf is valid for faito-mcp.dev.localhost" \
  bash -c 'openssl x509 -in certs/tls.crt -noout -checkhost faito-mcp.dev.localhost | grep -q "does match"'

finish
