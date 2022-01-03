### GCP

#### Create a project

Substitute your own project name.

```shell
gcloud projects create smallstep-dev
```

#### Create a bucket for terraform state

Substitute your own project, location, and bucket name (globally unique).

```shell
gsutil mb -p smallstep-dev -l US-WEST1 gs://acmecorp-smallstep-dev-terraform
```

### Terraform

#### Generate secrets

Terraform will need some secrets for various pieces of your infrastructure. Some of these secrets must be manually entered and others will be auto-generated. All secrets are stored on disk in the repository, encrypted by GCP Cloud KMS, and are safe to commit. Terraform will also automatically apply these secrets to your kubernetes cluster where needed.

```shell
./scripts/create-secrets.sh
```

After completion, several new files will exist in [`secrets/`](secrets/) (eg. `postgresql_password.enc`). They are safe to commit to be re-applied by terraform.

#### Configure GCS backend bucket in `backend.tf` for terraform state

Substitute your own GCP bucket name as created above.

```terraform
terraform {
  backend "gcs" {
    bucket = "acmecorp-smallstep-dev-terraform"
  }
}
```

#### Configure terraform

Open and edit [`config.tf`](config.tf) to match your GCP project settings.

#### Set up your default credentials

```shell
gcloud auth application-default login
```

#### Initialize and apply

```shell
terraform init
terraform apply
```

Terraform will generate a lock file that can be committed to your repository.
