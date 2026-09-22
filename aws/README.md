## AWS

Everything Smallstep Run Anywhere needs on AWS, in two Terraform roots
applied in order, and the modules they are built from.

```
aws/
  platform/    everything AWS: VPC (or yours), EKS, RDS PostgreSQL, ElastiCache Redis,
               KMS, Route 53, the CRL distribution point, SES SMTP, Secrets Manager
  workloads/   everything Kubernetes: the AWS Load Balancer Controller, a gp3 default
               StorageClass, Fluent Bit -> CloudWatch, and the bootstrap Job that creates
               the platform's databases and Kubernetes secrets
  modules/     network, dns, kms, eks, data, crl-bucket, iam-app, ses-smtp,
               cluster-addons, smallstep-bootstrap
```

Two roots because the Kubernetes and Helm providers in `workloads` are
configured from the cluster `platform` creates, and a provider cannot be
configured from a resource in the same apply. Each root has its own state and
is applied independently; `workloads` reads `platform`'s outputs through
remote state. Every module's header comment records why it is shaped the way
it is; every root's `variables.tf` documents its inputs, and
`terraform.tfvars.example` shows the values to set.

#### Requirements

- **Terraform >= 1.11**: S3-native state locking, write-only arguments and
  ephemeral resources (passwords are generated without ever landing in state).
- [`aws`](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html),
  [`kubectl`](https://kubernetes.io/docs/tasks/tools/) with the
  [kots plugin](https://docs.replicated.com/reference/kots-cli-getting-started),
  [`helm`](https://helm.sh/docs/helm/helm_install/).
- **A DNS zone you can delegate.** The platform is served under `base_domain`;
  its parent zone must carry an NS record for it before the application is
  installed. Let's Encrypt, the CloudFront certificate in the default CRL
  mode, and the application's preflights all resolve the names publicly.
- **An S3 bucket for state**, created once by hand with versioning on and
  Block Public Access on. Locking is S3-native (`use_lockfile`); no DynamoDB
  table. Each root's `backend.hcl.example` shows the backend configuration.

#### Order of operations

```shell
# 1. platform — about 25 minutes
cd aws/platform
cp backend.hcl.example backend.hcl            # set the bucket
cp terraform.tfvars.example terraform.tfvars  # set name, region, base_domain, your operator CIDRs
terraform init -backend-config=backend.hcl
terraform apply

# 2. delegate the zone in its parent, then confirm before continuing
terraform output route53_name_servers
dig NS <base_domain>

# 3. workloads — cluster addons and the bootstrap Job
cd ../workloads
cp backend.hcl.example backend.hcl            # same bucket, key workloads.tfstate
cp terraform.tfvars.example terraform.tfvars  # the state bucket platform used
aws eks update-kubeconfig --name <name> --region <region>
terraform init -backend-config=backend.hcl
terraform apply

# 4. install the application from your Replicated channel with the
#    configuration below, then point control.infra.<base_domain> at the
#    mission-control load balancer the install creates.
```

Delegation gates step 3 onwards: in the default `crl_mode`, `platform`'s
apply blocks on ACM DNS validation until the zone resolves, and the
application's install cannot issue its certificates without it.

#### What the roots leave in place

**platform** creates the VPC (three AZs, one NAT gateway per AZ, an S3
gateway endpoint) or takes yours (`create_vpc = false` with `vpc_id`,
`public_subnet_ids`, `private_subnet_ids`; only the load balancer role tags
are written to them); an EKS cluster with a managed node group from a launch
template (encrypted gp3 roots, IMDSv2), IRSA roles for the EBS CSI driver,
the load balancer controller, Fluent Bit and the bootstrap Job, and the
shared application role every platform service account assumes; RDS
PostgreSQL 16 and ElastiCache Redis, both encrypted under the platform KMS
key, TLS required, Redis AUTH on; a second, P-256 KMS key the gateway signs
API tokens with; the public Route 53 zone and every platform hostname
answering with the pre-allocated lobby EIPs (one per public subnet — the
application's NLB annotation requires the counts to match); the CRL
distribution point (below); SES SMTP; and every generated secret in Secrets
Manager under `<name>/app/*`, written with write-only arguments so no
password is ever in state. Bumping `db_password_version` rotates the generated
passwords in one apply.

**workloads** installs the AWS Load Balancer Controller (the application's
lobby Service is annotated for this controller and no other; without it the
Service never gets an address), a gp3 default StorageClass encrypted with the
platform key with EKS's gp2 demoted, Fluent Bit shipping container logs to a
CloudWatch log group `platform` created (`enable_logging`), and the bootstrap
Job. The Job runs in-cluster under its own IRSA role, reads the secrets from
Secrets Manager, creates the application role `smallstep` and the databases
`bouncer`, `gateway`, `guardian`, `inventory`, `mission_control` and
`landlord` (the application creates the rest at first boot), the
`landlordcachesrv` replication role, generates the OIDC JWKS, and creates the
Kubernetes secrets the application mounts: `auth`, `postgresql`, `redis`,
`redis-auth`, `private-issuer`, `smtp`, `majordomo-provisioner-password`,
`missioncontrol-provisioner-password`, `oidc`, `scim-server-secrets`,
`postgresql-landlordcachesrv`. Secrets never pass through Terraform.

What is deliberately not installed: cert-manager, ingress-nginx,
trust-manager and the Smallstep issuer are bundled in the application release,
and installing them a second time fights the bundled copies over CRDs and
webhooks. No service mesh; the current release needs none.

#### Outputs the application configuration uses

The Replicated (KOTS) configuration takes these `platform` outputs verbatim:

| Output | KOTS config item |
|---|---|
| `base_domain` | `base_domain` |
| `region` | `aws_region` (with `cloud_provider = aws`, `key_signer = kms`) |
| `app_iam_role_arn` | `aws_cluster_iam_role` — the role every platform service account assumes |
| `gateway_jwt_signing_key` | `gateway_jwt_signing_key` (`awskms:key-id=…`) |
| `gateway_jwt_signing_pubkey_b64` | `gateway_jwt_signing_pubkey` |
| `lobby_eip_allocation_ids` | `aws_nlb_ip`, comma-joined — the lobby NLB's static addresses |
| `rds_host`, `rds_port` | the PostgreSQL host and port, with the TLS option on (`rds.force_ssl = 1` is enforced) and the bundled PostgreSQL off |
| `redis_host`, `redis_port` | the Redis host and port, with TLS and AUTH on and the bundled Redis off |
| `smtp_host`, `smtp_port`, `smtp_username` | the SMTP settings; the password is in the `smtp` secret |

Secret-typed configuration items are left unset: the bootstrap Job has
already created the Kubernetes secrets the application mounts. The CRL bucket
name and URL are derived by the application from `base_domain`; they are
outputs here (`crl_bucket_name`, `crl_url`) for verification, not for
configuration.

#### The CRL distribution point

Every certificate the platform issues names `http://crl.<base_domain>/<file>`
as its CRL Distribution Point, and the platform writes those files to the
bucket `crl.<base_domain>`. Validators fetch that URL anonymously over plain
HTTP, so the bucket must answer anonymous plain-HTTP GETs. `crl_mode`
selects how:

- **`cloudfront`** (default): the bucket stays private — Block Public Access
  on, objects under a dedicated KMS key — and a CloudFront distribution with
  Origin Access Control is its only reader. The ACM certificate lives in
  us-east-1 (the only region CloudFront accepts certificates from; the root
  carries a second provider configuration for it). A freshly published CRL
  reaches every edge once the cache expires; CRLs carry their own freshness,
  and `aws cloudfront create-invalidation --paths '/*'` is the override.
  Not available in AWS GovCloud.
- **`public-bucket`**: S3 website hosting with a public-read policy and
  SSE-S3 — the one deliberately public bucket in the deployment. Not
  available if the account-level S3 Block Public Access setting is on.

#### Posture

The defaults are the documented production posture: six `m6i.xlarge`
workers, `db.m6i.large` Multi-AZ, `cache.m6g.large` Multi-AZ, a NAT gateway
per AZ, and `deletion_protection = true` (RDS deletion protection, a final
snapshot on destroy, 7-day recovery windows on secrets). An evaluation runs
on the smaller values commented in `terraform.tfvars.example` with
`deletion_protection = false`, which lets `terraform destroy` remove
everything cleanly.

Whatever the posture, the CA signing keys the platform creates inside KMS at
runtime are not managed by Terraform and survive a destroy; find them by alias
in the KMS console and schedule their deletion deliberately — that is what
destroys the CA.

#### Upgrading from 1.x

2.0.0 is a different layout, not an in-place change: the flat `//aws` module
is replaced by the `platform` and `workloads` roots and the modules under
`aws/modules`. There is no state migration; a 2.0.0 deployment is a new
deployment. The `1.1.0` and `1.2.0` tags remain for the flat module.

What changed in substance, beyond the layout: plain RDS PostgreSQL instead of
Aurora; the platform's databases and Kubernetes secrets are created by an
in-cluster Job instead of by hand and by Terraform data sources, so no
secret value is in state; the load balancer controller is a pinned
`helm_release` and the EBS CSI driver an EKS managed addon with its own IRSA
role, replacing `local-exec` and `kubectl apply` from a floating ref; the
default StorageClass is encrypted gp3; the module can create the VPC.
Variables were renamed to match: `default_name` → `name`,
`security_groups_cidr_blocks` → `api_public_access_cidrs`, `k8s_namespace` →
`namespace`, `subnets_public`/`subnets_private`/`vpc` →
`public_subnet_ids`/`private_subnet_ids`/`vpc_id` with `create_vpc = false`.
Not carried over: the YubiHSM PIN plumbing (KMS is the key manager on this
path), the `*.logs` record, the ICMP security group rules and the SCIM
temporary key script, and the `linkerd_inject` toggle (the namespace is created
without injection annotations; annotate it yourself if you run Linkerd
deliberately).
