# Changelog

## 1.2.0 (unreleased)

AWS module. The CRL distribution point serves anonymous plain HTTP, which CRL
clients require; it did not before. See `aws/README.md` "The CRL distribution
point" and "Upgrading from 1.1.x".

- `crl_mode`: `cloudfront` (default) keeps the bucket private behind a CloudFront distribution with Origin Access Control, a dedicated KMS key, and an ACM certificate in us-east-1; `public-bucket` is S3 website hosting with a public-read policy and SSE-S3.
- `crl.<base_domain>` is an alias record to the distribution or the website endpoint, not a CNAME to the S3 REST endpoint.
- Bucket ACLs removed (they fail on buckets created since 2023); `BucketOwnerEnforced` ownership on both buckets. The access-log bucket uses SSE-S3 and policy-based delivery, without which S3 delivers no logs.
- Outputs `crl_bucket_name`, `crl_url`, `crl_cloudfront_distribution_id`.

## 1.1.0 (unreleased)

AWS module. In-place fixes; no resource addresses change. See `aws/README.md`
"Upgrading from 1.0.x" for the changes that touch running infrastructure.

- Terraform `>= 1.9`, `aws >= 5.0, < 7.0`, `tls` declared. Validated on aws 6.66.
- `kms:CreateKey` was scoped to a key ARN and `s3:PutObject` to the bucket ARN; neither could ever authorize. The policy now matches what the platform does at runtime, and the role trusts every service account in the namespace.
- A P-256 KMS key for gateway JWT signing, with `gateway_jwt_signing_key` and `gateway_jwt_signing_pubkey_b64` outputs in the form the KOTS configuration expects.
- `missioncontrol-provisioner-password` and `redis-auth` Kubernetes secrets; Redis AUTH token (`ROTATE`); `rds.force_ssl = 1`.
- `rds_engine_version` is a string with a `>= 14` floor (default `16.4`); `eks_version` pinned (default `1.31`).
- Worker nodes from a launch template: encrypted gp3 root volumes (`node_root_volume_size`, default 100 GiB), IMDSv2 with hop limit 2. Replaces the node group.
- `cluster_endpoint_private_only`; `security_groups_cidr_blocks` required when the endpoint is public.
- DNS records `att`, `gateway`, `approvalq.infra`, `river.infra`; outputs `route53_att_domain`, `route53_gateway_domain` now names the REST API host and `route53_gateway_api_domain` the web ingress.
- Linkerd namespace annotation behind `linkerd_inject` (default false).
- The `null_resource` validation hack is a `validation` block; `data.http` uses `response_body`.
- Removed the orphaned `aws/lambda/` and `lambda.zip` (unwired since 1.0.4).

## 1.0.4 and earlier

See git history.
