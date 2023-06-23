# Azure

## Requirements
[`step`](https://github.com/smallstep/cli)

[`az`](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)

## Secrets Management

Terraform will need some secrets for various pieces of your infrastructure.
Some of these secrets must be manually entered and others will be auto-generated.
All secrets are stored in Key Vault and referenced by the Terraform state. (This is a separate Key Vault from the one created to hold private keys of each authority in Certificate Manager).
Terraform will also automatically apply these secrets to your Kubernetes cluster where needed.

On first apply, make sure to pass in the values of the following variables to create the secrets for your private issuer password and SMTP password and optionally for your Yubi HSM pin.

* private_issuer_password
* smtp_password
* yubihsm_pin (optional)

Our recommendation is creating high-level variables with a default value of an empty string to pass into the module block; subsequently, you can pass in the actual secrets during your first Terraform apply of the module. These variables are marked "secret" in Terraform to avoid leaking them in Terraform's responses on the command line, and we recommend passing the command line `HISTCONTROL=ignorespace` before running your apply to prevent leaking secrets into your session history. (If you are using a YubiHSM2 and have set the value of `hsm_enabled = true`, also pass in the HSM PIN code in hexadecimal and password to variable `yubihsm_pin`. For example, authentication key id `0x0001` with password `password` would follow the form: -var yubihsm_pin="0001password")

You may instead pass in these values directly to the module block, but the above method will prevent these secrets from being written to your source control. All related resources are configured to ignore changes, so it won't matter that these values will not be passed in for subsequent Terraform applies.

Landlord and Veto microservices use [Workload Identity](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview) for accessing Key Vault and Blob Storage, respectively.

## Example Module Instantiation

```terraform
terraform {
  backend "azurerm" {
    resource_group_name  = "Terraform"
    storage_account_name = "smallstepterraform"
    container_name       = "onprem"
    key                  = "onprem.tfstate"
  }
}

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
  description = "Yubi HSM PIN"
  type        = string
  sensitive   = true
}

provider "azurerm" {
  features {}
}


module "run_anywhere" {
  source = "github.com/smallstep/run-anywhere-terraform.git//azure"

  base_domain             = "azure.example.com"
  resource_group_name     = "smallstep"
  private_issuer_password = var.private_issuer_password
  smtp_password           = var.smtp_password
  yubihsm_pin             = var.yubihsm_pin
  yubihsm_enabled         = true
}

output "output" {
  value = module.run_anywhere

  sensitive = true
}
```

```shell
terraform init
HISTCONTROL=ignorespace

terraform apply -var private_issuer_password="${private_issuer_password}" -var smtp_password="${smtp_password}" -var yubihsm_pin="${yubihsm_auth_id}${yubihsm_pin}"
```

## TODO

* Use private endpoint for Postgres and disable public network access.
* Setup DNS to avoid having to create a custom hosts configuration for the Redis prviate endpoint since this IP can change.
* Option to provide credentials for scim-server.
