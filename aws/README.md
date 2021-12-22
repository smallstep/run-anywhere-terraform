### Initialize and apply with secrets

Terraform will need some secrets for various pieces of your infrastructure. Some of these secrets must be manually entered and others will be auto-generated. All secrets are stored in AWS SecretsManager, encrypted by AWS KMS, and referenced by the Terraform state. Terraform will also automatically apply these secrets to your kubernetes cluster where needed.

On first apply, make sure to pass in the values of the following two variables to create the secrets for your private issuer password and SMTP password. Both variables are marked "secret" in Terraform to avoid leaking them in Terraform's responses on the command line, and we pass in `HISTCONTROL=ignorespace` to prevent leaking secrets into your session history. (If you are using a YubiHSM2 and have set the value of `hsm_enabled = true`, also pass in the HSM PIN code in hexadecimal and password to variable `yubihsm_pin`. For example, authentication key id `0x0001` with password `password` would follow the form: -var yubihsm_pin="0001password")
```shell
terraform init
HISTCONTROL=ignorespace
terraform apply -var private_issuer_password="${private_issuer_password}" -var smtp_password="${smtp_password}"
```

You may instead pass in these values when adding the module block, but the above method will prevent these secrets from being written to your source control. All related resources are configured to ignore subsequent changes, so it won't matter that these values will not be passed in for subsequent Terraform applies.

After completion, Terraform will have stood up and configured an RDS Aurora PostgreSQL cluster (with lambda attached), an EKS cluster, a Redis instance, an Elastic IP (later used to create an NLB), DNS resources, and all secrets stored in SecretsManager. Additionally, it will have tagged all subnets involved to allow EKS to attach to the private subnets and our NLB to attach to the public subnets.