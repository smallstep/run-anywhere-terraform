## GCP

#### Requirements
[`step`](https://github.com/smallstep/cli)
[`gcloud`](https://cloud.google.com/sdk/docs/install)

#### Generate secrets

Terraform will need some secrets for various pieces of your infrastructure. Some of these secrets must be manually entered and others will be auto-generated. All secrets are stored on disk in the location of your choice, encrypted by GCP Cloud KMS, and are safe to commit. Terraform will also automatically apply these secrets to your kubernetes cluster where needed. When instantiating this module, you must pass the relative path to these secrets to variable `path_to_secrets`, so it is recommended to store them in a directory within your Terraform workspace.

To run the [script that generates and encrypts project secrets](https://gist.github.com/J-Hunter-Hawke/cb4314104a0ac250d31ec09e5f2c377d), you must have the [`step`](https://github.com/smallstep/cli) and [`gcloud`](https://cloud.google.com/sdk/docs/install) CLI utilities installed and configured.

After completion, several new files will exist (eg. `postgresql_password.enc`). They are safe to commit to be re-applied by terraform.

#### Set up your credentials

```shell
gcloud auth application-default login

curl https://gist.githubusercontent.com/J-Hunter-Hawke/cb4314104a0ac250d31ec09e5f2c377d/raw > create_gcp_secrets.sh
chmod +x ./create_gcp_secrets && ./create_gcp_secrets.sh
mv ./secrets /path/to/terraform/secrets
```

#### Example module intantiation

```terraform
module "run_anywhere" {
  source = "github.com/smallstep/run-anywhere-terraform.git//gcp?ref=v1.0.0"

  base_domain             = "something.com"
  path_to_secrets         = "${path.module}/secrets"
  project_id              = "smallstep"
  region                  = "us-central1"
  zone                    = "us-central1-c"
}
```

#### Initialize and apply

```shell
terraform init
terraform apply
```

Terraform will generate a lock file that can be committed to your repository.