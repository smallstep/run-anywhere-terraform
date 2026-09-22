## AWS

#### Requirements

[`step`](https://github.com/smallstep/cli)

[`aws`](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)

[`helm`](https://helm.sh/docs/helm/helm_install/)

#### Secret management

Terraform will need some secrets for various pieces of your infrastructure. Some of these secrets must be manually entered and others will be auto-generated. All secrets are stored in AWS SecretsManager, encrypted by AWS KMS, and referenced by the Terraform state. Terraform will also automatically apply these secrets to your kubernetes cluster where needed.

On first apply, make sure to pass in the values of the following two variables to create the secrets for your private issuer password and SMTP password. Our recommendation is creating two high-level variables with a default value of an empty string to pass into the module block; subsequently, you can pass in the actual secrets during your first Terraform apply of the module. Both variables are marked "secret" in Terraform to avoid leaking them in Terraform's responses on the command line, and we recommend passing the command line `HISTCONTROL=ignorespace` before running your apply to prevent leaking secrets into your session history. (If you are using a YubiHSM2 and have set the value of `hsm_enabled = true`, also pass in the HSM PIN code in hexadecimal and password to variable `yubihsm_pin`. For example, authentication key id `0x0001` with password `password` would follow the form: -var yubihsm_pin="0001password")

You may instead pass in these values directly to the module block, but the above method will prevent these secrets from being written to your source control. All related resources are configured to ignore changes, so it won't matter that these values will not be passed in for subsequent Terraform applies.

Once the module has been set up, you should confirm each secret's value in the SecretsManager console. If incorrect, you can fix the secret directly in the console without disrupting the Terraform module.

After completion, Terraform will have stood up and configured an RDS Aurora PostgreSQL cluster, an EKS cluster, a Redis instance with AUTH enabled, one Elastic IP per public subnet (later used to create the NLB), DNS resources, the CRL distribution point (see below), the KMS keys (a symmetric key for encryption and a P-256 key the gateway signs API tokens with), and all secrets stored in SecretsManager. Additionally, it will have tagged all subnets involved to allow EKS to attach to the private subnets and our NLB to attach to the public subnets.

The module does **not** create the platform's PostgreSQL databases. Create them on the Aurora cluster before installing the application; the install documentation lists them.

#### Example module instantiation

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
  source = "github.com/smallstep/run-anywhere-terraform.git//aws?ref=1.2.0"

  base_domain                 = "your_domain.com"
  default_name                = "smallstep-prod"
  private_issuer_password     = var.private_issuer_password
  region                      = "us-west-1"
  smtp_password               = var.smtp_password
  subnets_public              = ["subnet-abskd939", "subnet-283kdjjd9"]
  subnets_private             = ["subnet-d7ddd333b3", "subnet-abscd303"]
  vpc                         = "vpc-89d606ae"
  security_groups_cidr_blocks = ["192.168.71.100/32"]   # operator ranges; required unless the endpoint is private-only
  yubihsm_enabled             = true
  yubihsm_pin                 = var.yubihsm_pin

  # eks_version                   = "1.31"   # pinned; set to your cluster's current version when adopting the module
  # rds_engine_version            = "16.4"   # Aurora PostgreSQL; the platform requires 14 or newer
  # cluster_endpoint_private_only = false    # true: API server reachable only from the VPC
  # linkerd_inject                = false    # the current release needs no service mesh
  # crl_mode                      = "cloudfront"  # or "public-bucket"; see "The CRL distribution point"
}
```

#### Outputs the application configuration uses

The Replicated (KOTS) configuration takes these values verbatim:

| Output | KOTS config item |
|---|---|
| `iam_service_account_arn` | `aws_cluster_iam_role` — the role every platform service account assumes |
| `gateway_jwt_signing_key` | `gateway_jwt_signing_key` (`awskms:key-id=…`) |
| `gateway_jwt_signing_pubkey_b64` | `gateway_jwt_signing_pubkey` |
| `route53_gateway_domain` | the REST/GraphQL API host, `gateway.<base>` — not `gateway.api.<base>`, which is the web application's own ingress |
| `redis_auth_secret_arn` | the Redis AUTH token; the same value is placed in the `redis-auth` Kubernetes secret, so set `redis_auth_enabled` and `redis_require_tls` |
| `rds_cluster_endpoint`, `rds_cluster_port` | the database host and port; the cluster requires TLS (`rds.force_ssl=1`), so set the PostgreSQL TLS option |

Secrets the module places in the `smallstep` namespace: `auth`, `postgresql`, `redis-auth`, `smtp`, `oidc`, `private-issuer`, `majordomo-provisioner-password`, `missioncontrol-provisioner-password`, `scim-server-secrets`, and `yubihsm2-pin` when enabled.

#### The CRL distribution point

Every certificate the platform issues names `http://crl.<base_domain>/<file>` as its CRL Distribution Point, and the platform writes those files to the bucket `crl.<base_domain>` (it derives the name from the base domain; it is not configurable). Validators fetch the URL anonymously over plain HTTP — a client cannot be required to complete a TLS handshake to check revocation of the certificate the handshake depends on — so the bucket must answer anonymous plain-HTTP GETs. `crl_mode` selects how:

- **`cloudfront`** (default): the bucket stays private — Block Public Access on, objects encrypted under a dedicated KMS key — and a CloudFront distribution with Origin Access Control is its only reader. The module creates the distribution, an ACM certificate for `crl.<base_domain>` in us-east-1 (the only region CloudFront accepts certificates from; the module carries its own `us-east-1` provider configuration for this), and the DNS validation records. **The apply blocks on certificate validation until the zone is delegated from its parent.** A freshly published CRL reaches every edge once the cache expires; CRLs carry their own freshness (`nextUpdate`), so that is normally fine, and `aws cloudfront create-invalidation --distribution-id $(terraform output -raw crl_cloudfront_distribution_id) --paths '/*'` is the manual override.
- **`public-bucket`**: S3 website hosting with a public-read bucket policy and SSE-S3. The one deliberately public bucket in the deployment; objects are served the moment they are written. Not available if the account-level S3 Block Public Access setting is on.

Both modes serve the same `crl_url` output. CloudFront is not available in every partition (it is absent from AWS GovCloud); use `public-bucket` there.

#### Upgrading from 1.1.x

1.2.0 changes the CRL bucket and its DNS record. Previously the bucket was private with SSE-KMS under the project key and `crl.<base_domain>` was a CNAME to the S3 REST endpoint, so anonymous CRL fetches failed and revocation checking never happened.

- **Pick `crl_mode` before applying.** The default, `cloudfront`, creates a distribution, an ACM certificate in us-east-1 and a second KMS key, and the apply waits for DNS validation of the certificate. `public-bucket` makes the bucket public.
- **`crl.<base_domain>` is replaced**: the CNAME becomes an alias record (a type change replaces the record). Expect a short window where the name does not resolve.
- **Objects written before the upgrade stay encrypted under the project key** and are not readable in either mode until rewritten. The platform republishes its CRLs on its next cycle; to serve them immediately, re-encrypt in place: `aws s3 cp --recursive s3://crl.<base_domain>/ s3://crl.<base_domain>/`.
- **ACLs are gone.** Both buckets move to `BucketOwnerEnforced` ownership and the two `aws_s3_bucket_acl` resources are removed from configuration (a no-op on the buckets). Access logging is authorized by bucket policy instead, and the log bucket switches to SSE-S3, which is the only encryption S3 will deliver access logs to.
- New outputs: `crl_bucket_name`, `crl_url`, `crl_cloudfront_distribution_id`.

#### Upgrading from 1.0.x

1.1.0 changes existing infrastructure. Read this before `terraform apply`:

- **Set `eks_version` and `rds_engine_version` to your current versions** before applying. Both were previously unpinned or lower; the new defaults (`"1.31"`, `"16.4"`) would otherwise plan a cluster upgrade. `rds_engine_version` is now a string.
- **The node group is replaced.** Worker nodes now come from a launch template (encrypted root volumes, IMDSv2). EKS rolls the nodes; plan for a maintenance window.
- **Redis gains an AUTH token** (`ROTATE` strategy, applied in place). The platform must be configured to present it — enable Redis AUTH in the application configuration and use the `redis-auth` secret this module creates — or it will be unable to connect once the token is required.
- **PostgreSQL requires TLS** (`rds.force_ssl = 1`). Enable the PostgreSQL TLS option in the application configuration.
- **`security_groups_cidr_blocks` is required** unless `cluster_endpoint_private_only = true`. An empty list with a public endpoint is refused.
- **The Linkerd injection annotation is off by default** (`linkerd_inject = false`). Set it to `true` only if you run Linkerd deliberately.
- **The service-account role now trusts every service account in the namespace**, not only `landlord` — the release annotates several service accounts with this role.
- **The application IAM policy is corrected**: `kms:CreateKey` on `*` (it cannot be resource-scoped) and S3 object actions on `<bucket>/*`. Both grants were previously unusable.
- New DNS records: `att`, `gateway`, `approvalq.infra`, `river.infra`. New Kubernetes secrets: `missioncontrol-provisioner-password`, `redis-auth`.

#### Initialize and apply

```shell
terraform init
HISTCONTROL=ignorespace
PRIVATE_ISSUER_PASSWORD=supersecretpassword
SMTP_PASSWORD=supersecretpasswordagain
YUBIHSM_PIN=0x04d2abc
terraform apply -var private_issuer_password="${PRIVATE_ISSUER_PASSWORD}" -var smtp_password="${SMTP_PASSWORD}" -var yubihsm_pin="${YUBIHSM_PIN}"
```
