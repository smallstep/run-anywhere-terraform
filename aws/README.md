## AWS

#### Requirements
[`step`](https://github.com/smallstep/cli)
[`aws`](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)

#### Secret management

Terraform will need some secrets for various pieces of your infrastructure. Some of these secrets must be manually entered and others will be auto-generated. All secrets are stored in AWS SecretsManager, encrypted by AWS KMS, and referenced by the Terraform state. Terraform will also automatically apply these secrets to your kubernetes cluster where needed.

On first apply, make sure to pass in the values of the following two variables to create the secrets for your private issuer password and SMTP password. Our recommendation is creating two high-level variables with a default value of an empty string to pass into the module block; subsequently, you can pass in the actual secrets during your first Terraform apply of the module. Both variables are marked "secret" in Terraform to avoid leaking them in Terraform's responses on the command line, and we recommend passing the command line `HISTCONTROL=ignorespace` before running your apply to prevent leaking secrets into your session history. (If you are using a YubiHSM2 and have set the value of `hsm_enabled = true`, also pass in the HSM PIN code in hexadecimal and password to variable `yubihsm_pin`. For example, authentication key id `0x0001` with password `password` would follow the form: -var yubihsm_pin="0001password")

You may instead pass in these values directly to the module block, but the above method will prevent these secrets from being written to your source control. All related resources are configured to ignore changes, so it won't matter that these values will not be passed in for subsequent Terraform applies.

Once the module has been set up, you should confirm each secret's value in the SecretsManager console. If incorrect, you can fix the secret directly in the console without disrupting the Terraform module.

After completion, Terraform will have stood up and configured an RDS Aurora PostgreSQL cluster (with lambda attached), an EKS cluster, a Redis instance, an Elastic IP (later used to create an NLB), DNS resources, and all secrets stored in SecretsManager. Additionally, it will have tagged all subnets involved to allow EKS to attach to the private subnets and our NLB to attach to the public subnets.

#### Example module intantiation

```terraform
variable "private_issuer_password" {
  default     = ""
  description = "Private issuer password used for the `run anywhere` deployment, set during first module apply and left blank otherwise."
  type        = string
  sensitive   = true
}

variable "smtp_password" {
  default     = ""
  description = "SMTP password used for the `run anywhere` deployment, set during first module apply and left blank otherwise."
  type        = string
  sensitive   = true
}

variable "yubihsm_pin" {
  default     = ""
  description = "YubiHSM PIN followed by password for the `run anywhere` deployment, set during first module apply and left blank otherwise."
  type        = string
  sensitive   = true
}

module "run_anywhere" {
  source = "github.com/smallstep/run-anywhere-terraform.git//aws?ref=v1.0.0"

  base_domain             = "your_domain.com"
  default_name            = "smallstep-prod"
  private_issuer_password = var.private_issuer_password
  region                  = "us-west-1"
  smtp_password           = var.smtp_password
  subnets_public          = ["subnet-abskd939", "subnet-283kdjjd9"]    
  subnets_private         = ["subnet-d7ddd333b3", "subnet-abscd303"]    
  yubihsm_enabled         = true
  yubihsm_pin             = var.yubihsm_pin
}
```

#### Initialize and apply

```shell
terraform init
HISTCONTROL=ignorespace
terraform apply -var private_issuer_password="${private_issuer_password}" -var smtp_password="${smtp_password}" -var yubihsm_pin="${yubihsm_pin}"
```