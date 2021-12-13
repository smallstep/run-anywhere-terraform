#!/usr/bin/env bash

set -e
dir=$(dirname "${BASH_SOURCE[0]}")

echo -e "\Generating temporary SCIM secret key"
step crypto keypair key_pub key_priv --force --no-password --insecure
echo -e "\Uploading temporary SCIM secret key to SecretsManager: $secret_id"
aws secretsmanager put-secret-value --secret-id $secret_id --secret-string file://key_priv

rm key_priv key_pub