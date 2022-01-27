#!/usr/bin/env bash
# Generates secrets for the GCP `run anywhere` deployment

set -e

# define key names for each secret
declare -A SECRETS
SECRETS[postgresql]=password
SECRETS[auth]=secret
SECRETS[majordomo-provisioner-password]=password
SECRETS[oidc]=jwks
SECRETS[smtp]=password
SECRETS[private-issuer]=password
SECRETS[yubihsm2-pin]="pin.txt"

dir=$(dirname "${BASH_SOURCE[0]}")

function generate_secret() {
    cat /dev/urandom | head -c 32 | step base64 -u -r | xargs -r echo -n 2> /dev/null
}

function generate_oidc_jwks() {
    echo -n "{\"keys\": [$(step crypto jwk create /dev/null /dev/stdout --kty RSA --force --no-password --insecure 2> /dev/null &)]}"
}

function create_terraform_secret() {
    echo -e "\nEncrypting terraform secret $1.enc..."
    if [ ! -f $dir/secrets/$1.enc ]; then
        gcloud kms encrypt --project $gcp_project_id --location global --keyring smallstep-terraform --key terraform-secret --plaintext-file=$2 --ciphertext-file=$dir/secrets/$1.enc
    else
        echo -e "Skipping secret creation for $1.enc (already exists)..."
    fi
}
# prompt for GCP project id
read -p "GCP project ID: " gcp_project_id
export GCP_PROJECT=$gcp_project_id

# prompt for smtp password
if [ ! -f $dir/../secrets/smtp_password.enc ]; then
  read -sp "SMTP password: " smtp_password
fi

# prompt for private-issuer provisioner password
if [ ! -f $dir/../secrets/private-issuer_password.enc ]; then
    echo -e "\n"
    read -sp "private-issuer provisioner password (skip unless needed for custom public TLS): " private_issuer_password
fi

# prompt for YubiHSM2 pin
if [ ! -f $dir/../secrets/yubihsm2_pin.enc ]; then
    echo -e "\n"
    read -sp "YubiHSM2 PIN (skip unless using YubiHSM2): " yubihsm2_pin
fi

echo -e "\n"

# create the keyring and key for terraform
gcloud kms keyrings create smallstep-terraform --project $gcp_project_id --location global 2> /dev/null || true
gcloud kms keys create terraform-secret --keyring smallstep-terraform --project $gcp_project_id --location global --purpose "encryption" 2> /dev/null || true

mkdir -p secrets

# create encrypted terraform secrets
create_terraform_secret postgresql_password <(generate_secret)
create_terraform_secret auth_secret <(generate_secret)
create_terraform_secret majordomo-provisioner-password_password <(generate_secret)
create_terraform_secret oidc_jwks <(generate_oidc_jwks)
create_terraform_secret smtp_password <(echo -n $smtp_password)
create_terraform_secret private-issuer_password <(echo -n $private_issuer_password)
create_terraform_secret yubihsm2_pin <(echo -n $yubihsm2_pin)