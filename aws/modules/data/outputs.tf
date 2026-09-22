# Consumed by platform/outputs.tf, which re-exports these to workloads (the
# bootstrap job) and to the install tooling. The secret_arns keys are contract:
# the root merges { smtp = ... } from modules/ses-smtp into this map, and the
# consumers index it by these exact names — renaming one here breaks a shell
# script two stages away, not a Terraform plan.

output "rds_host" {
  # .address, NOT .endpoint: endpoint is "host:port" and the KOTS config
  # wants a bare hostname — a stray ":5432" inside the rendered DSN is a
  # connection failure that presents as a DNS error.
  description = "Bare RDS hostname, no port."
  value       = aws_db_instance.this.address
}

output "rds_port" {
  value = aws_db_instance.this.port
}

output "redis_host" {
  # Primary endpoint (cluster mode is off). Follows automatic failover when
  # redis_multi_az is on.
  value = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "redis_port" {
  value = aws_elasticache_replication_group.this.port
}

output "secret_arns" {
  description = "Secrets Manager ARNs keyed by short name. All values are write-only mirrors — no secret material transits this output, only ARNs."
  value = merge(
    { for k, s in aws_secretsmanager_secret.app : k => s.arn },
    {
      master     = aws_secretsmanager_secret.master.arn
      redis_auth = aws_secretsmanager_secret.redis_auth.arn
    },
  )
}
