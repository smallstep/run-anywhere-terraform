#!/usr/bin/env bash
set -euo pipefail
# Generate an OIDC signing JWKS and store it in Azure Key Vault.
# Run this AFTER the Key Vault has been created (terraform apply -target=azurerm_key_vault.secrets),
# then run terraform apply for the full deployment.
#
# Usage: VAULT=<vault-name> ./create_oidc_secret.sh
VAULT="${VAULT:?VAULT env var required}"
JWKS=$(step crypto jwk create /dev/null /dev/stdout \
  --kty RSA --force --no-password --insecure 2>/dev/null \
  | python3 -c "import sys,json; k=json.load(sys.stdin); print(json.dumps({'keys':[k]}))")
az keyvault secret set --vault-name "$VAULT" --name oidcjwk --value "$JWKS"
echo "OIDC JWK stored in Key Vault: $VAULT"
