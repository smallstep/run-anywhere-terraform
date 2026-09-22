variable "name" {
  description = "Deployment name, used for app.kubernetes.io/part-of labels."
  type        = string
}

variable "region" {
  description = "AWS region the bootstrap Job reads Secrets Manager in."
  type        = string
}

variable "namespace" {
  description = "Namespace the KOTS app installs into. Created by this module; every script and the shared IRSA trust policy are scoped to it."
  type        = string
}

variable "bootstrap_role_arn" {
  description = "IRSA role the bootstrap Job assumes. Its trust policy pins <namespace>:smallstep-bootstrap, so the service account name here is not a free choice."
  type        = string
}

variable "rds_host" {
  description = "RDS endpoint hostname the init-db stage connects to as the master user."
  type        = string
}

variable "rds_port" {
  description = "RDS port."
  type        = number
}

variable "app_secret_arns" {
  description = "Secrets Manager ARNs keyed by short name — stage 1's app_secret_arns output, passed through verbatim. The fetch-secrets stage reads all ten so a bad ARN or missing IAM grant fails in the stage named for it."
  type        = map(string)

  validation {
    condition = length(setsubtract([
      "master",
      "postgres_app",
      "postgres_landlordcachesrv",
      "redis_auth",
      "auth_secret",
      "private_issuer",
      "majordomo_provisioner",
      "mission_control_provisioner",
      "kots_admin_password",
      "smtp",
    ], keys(var.app_secret_arns))) == 0
    error_message = "app_secret_arns must contain keys: master, postgres_app, postgres_landlordcachesrv, redis_auth, auth_secret, private_issuer, majordomo_provisioner, mission_control_provisioner, kots_admin_password, smtp."
  }
}
