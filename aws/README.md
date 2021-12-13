### AWS

#### Create a bucket for Terraform state

Substitute your own bucket name (globally unique). S3 Buckets are global and do not exist in a single region.

```shell
aws s3 mb s3://mybucket
```

From here, make sure to enable bucket encryption, set up versioning, write a bucket policy, and disable all public access. Your Terraform state should be considered sensitive information, so you should take all precautions possible in securing the S3 bucket storing it.

> Security around the S3 bucket storing the Terraform state is at the discretion of the organization hosting this on-prem solution. Smallstep is not liable for bucket misconfigurations leaking sensitive data.

***

### Terraform

#### Configure AWS backend bucket in `backend.tf` for terraform state

Substitute your own AWS bucket name as created above.

```terraform
terraform {
  backend "aws" {
    bucket  = "acmecorp-smallstep-dev-terraform"
    key     = "smallstep/terraform.tfstate"
    region  = "us-west-1"
    encrypt = true
  }
  ...
}
```

#### Configure terraform

Open and edit [`config.tf`](config.tf) to match your AWS project settings.

#### Initialize and apply

Terraform will need some secrets for various pieces of your infrastructure. Some of these secrets must be manually entered and others will be auto-generated. All secrets are stored in AWS SecretsManager, encrypted by AWS KMS, and referenced by the Terraform state. Terraform will also automatically apply these secrets to your kubernetes cluster where needed.

On first apply, make sure to pass in the values of the following two variables to create the secrets for your private issuer password and SMTP password. Both variables are marked "secret" in Terraform to avoid leaking them in Terraform's responses on the command line. (If you are using a YubiHSM2 and have set the value of `hsm_enabled = true` in `config.tf`, also pass in the HSM PIN code and password to variable `hsm_pin`. For example, authentication key id `0x0001` with password `password` would follow the form: -var hsm_pin="0001password")
```shell
terraform init
terraform apply -var private_issuer_password="${private_issuer_password}" -var smtp_password="${smtp_password}"
```

After completion, Terraform will have stood up and configured an RDS Aurora PostgreSQL cluster (with lambda attached), an EKS cluster, a Redis instance, an Elastic IP (later used to create an NLB), DNS resources, and all secrets stored in SecretsManager. Additionally, it will have tagged all subnets involved to allow EKS to attach to the private subnets and our NLB to attach to the public subnets.

Terraform will generate a lock file that can be committed to your repository. If you are working in a team, this lock file can be configured to use a DynamoDB table instead (not included in given code).