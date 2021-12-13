#!/usr/bin/env bash

set -e
dir=$(dirname "${BASH_SOURCE[0]}")

touch jwk_priv

echo -e "\Generating OIDC JWK secret"
echo -n "{\"keys\": [$(step crypto jwk create /dev/null /dev/stdout --kty RSA --force --no-password --insecure 2> /dev/null)]}" > jwk_priv
echo -e "\Uploading OIDC secret to SecretsManager: $secret_id"
aws secretsmanager put-secret-value --secret-id $secret_id --secret-string file://jwk_priv

rm jwk_priv