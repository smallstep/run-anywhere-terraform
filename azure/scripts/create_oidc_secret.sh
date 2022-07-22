az keyvault secret set \
    --name oidcjwk \
    --vault-name $VAULT \
    --value "{\"keys\": [$(step crypto jwk create /dev/null /dev/stdout --kty RSA --force --no-password --insecure 2> /dev/null)]}"
