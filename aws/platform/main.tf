# Stage 1 of 2: everything AWS, nothing Kubernetes. workloads configures
# its kubernetes/helm providers from this root's outputs (a provider cannot be
# configured from a resource created in the same apply), and the KOTS
# configuration is rendered from `terraform output -json` (see the README).
#
# The module graph below is the contract. Each module's header comment records
# why it is shaped the way it is; this file only wires them.

module "network" {
  source = "../modules/network"

  name               = var.name
  create_vpc         = var.create_vpc
  vpc_cidr           = var.vpc_cidr
  az_count           = var.az_count
  single_nat_gateway = var.single_nat_gateway
  vpc_id             = var.vpc_id
  public_subnet_ids  = var.public_subnet_ids
  private_subnet_ids = var.private_subnet_ids
}

module "dns" {
  source = "../modules/dns"

  domain               = var.base_domain
  lobby_eip_public_ips = module.network.lobby_eip_public_ips
}

module "kms" {
  source = "../modules/kms"

  name                = var.name
  deletion_protection = var.deletion_protection
}

module "eks" {
  source = "../modules/eks"

  name                          = var.name
  cluster_version               = var.eks_version
  vpc_id                        = module.network.vpc_id
  private_subnet_ids            = module.network.private_subnet_ids
  cluster_endpoint_private_only = var.cluster_endpoint_private_only
  api_public_access_cidrs       = var.api_public_access_cidrs
  node_instance_type            = var.eks_node_instance_type
  node_desired                  = var.eks_node_desired
  node_min                      = var.eks_node_min
  node_max                      = var.eks_node_max
  kms_key_arn                   = module.kms.platform_key_arn
  enable_logging                = var.enable_logging
  namespace                     = var.namespace
  app_secrets_prefix            = "${var.name}/app"
}

module "data" {
  source = "../modules/data"

  name                   = var.name
  vpc_id                 = module.network.vpc_id
  private_subnet_ids     = module.network.private_subnet_ids
  node_security_group_id = module.eks.node_security_group_id
  kms_key_arn            = module.kms.platform_key_arn
  db_instance_class      = var.db_instance_class
  db_multi_az            = var.db_multi_az
  db_password_version    = var.db_password_version
  redis_node_type        = var.redis_node_type
  redis_multi_az         = var.redis_multi_az
  deletion_protection    = var.deletion_protection
}

module "crl_bucket" {
  source = "../modules/crl-bucket"

  providers = {
    aws      = aws
    aws.use1 = aws.use1
  }

  domain              = var.base_domain
  zone_id             = module.dns.zone_id
  crl_mode            = var.crl_mode
  kms_key_arn         = module.kms.platform_key_arn
  deletion_protection = var.deletion_protection
}

module "iam_app" {
  source = "../modules/iam-app"

  name                = var.name
  namespace           = var.namespace
  oidc_provider_arn   = module.eks.oidc_provider_arn
  crl_bucket_arn      = module.crl_bucket.bucket_arn
  gateway_jwt_key_arn = module.kms.gateway_jwt_key_arn
}

module "ses_smtp" {
  source = "../modules/ses-smtp"

  name                = var.name
  domain              = var.base_domain
  zone_id             = module.dns.zone_id
  smtp_mode           = var.smtp_mode
  kms_key_arn         = module.kms.platform_key_arn
  deletion_protection = var.deletion_protection
}
