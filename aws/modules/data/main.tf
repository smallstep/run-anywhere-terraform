# App data stores and generated secrets: one RDS PostgreSQL instance, one
# ElastiCache Redis replication group, and every application secret the
# platform bootstrap consumes, mirrored into Secrets Manager under
# "<name>/app/*". The platform root merges the SES SMTP credentials
# (modules/ses-smtp) into the same map — SMTP is deliberately NOT created
# here, because its lifecycle is tied to the SES identity, not the data tier.
#
# Plain RDS PostgreSQL, not Aurora: the platform needs a standard PostgreSQL
# endpoint and nothing more. Multi-AZ and the instance class are variables:
# the defaults are a single-AZ evaluation size; production flips db_multi_az
# and the instance class without touching this file.
#
# var.deletion_protection, stated once: true (the default) turns on RDS
# deletion protection, takes a final snapshot on destroy, and keeps 7-day
# recovery windows on every secret; false is the evaluation posture, where
# `terraform destroy` completes cleanly and leaves nothing behind. There is
# deliberately NO prevent_destroy lifecycle block in either posture: it fails
# a destroy mid-graph and leaves half the VPC gone, where deletion_protection
# refuses the destroy up front.
#
# Every secret value is generated in-module via the ephemeral + write-only
# pattern (see the long comment above the master password below). One
# exception: the Redis auth token must live in state, because the provider
# gives it no write-only argument. That exception is fenced and documented
# where it happens.

locals {
  # App-level secrets that are opaque generated strings: key = the exact map
  # key the platform output contract promises, value = the kebab-case
  # Secrets Manager name segment. master and redis-auth are NOT in this map —
  # master carries a JSON document and redis-auth has a different generation
  # path (see below) — but their output keys join these in outputs.tf.
  app_secret_names = {
    postgres_app                = "postgres-app"
    postgres_landlordcachesrv   = "postgres-landlordcachesrv"
    auth_secret                 = "auth-secret"
    private_issuer              = "private-issuer"
    majordomo_provisioner       = "majordomo-provisioner"
    mission_control_provisioner = "mission-control-provisioner"
    kots_admin_password         = "kots-admin-password"
  }
}

# --- RDS PostgreSQL ----------------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-app"
  subnet_ids = var.private_subnet_ids

  tags = { Name = "${var.name}-app" }
}

resource "aws_security_group" "rds" {
  name        = "${var.name}-rds"
  description = "PostgreSQL from EKS worker nodes only"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-rds" }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_nodes" {
  description                  = "PostgreSQL from EKS worker nodes"
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = var.node_security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

# Unrestricted egress, deliberately: SG rules are stateful so replies to
# inbound sessions never need it, but the managed engine's own maintenance
# and telemetry paths do, and restricting those breaks in ways AWS does not
# document. There is nothing to protect by narrowing it — the SG's job here
# is the ingress rule above.
resource "aws_vpc_security_group_egress_rule" "rds_all" {
  description       = "Engine-initiated outbound (maintenance, telemetry)"
  security_group_id = aws_security_group.rds.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_db_parameter_group" "postgres16" {
  name   = "${var.name}-app-postgres16"
  family = "postgres16"

  # Backs the KOTS config's pg_require_tls: the server refuses
  # non-TLS connections outright, rather than the clients merely preferring
  # TLS. Dynamic parameter, applies immediately.
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  # Required for the landlordcachesrv logical-replication HA path (it consumes
  # a replication slot on the app database). Static parameter: pending-reboot
  # is the only legal apply_method, and a fresh instance picks it up at first
  # boot — but changing it on a live instance needs a manual reboot even with
  # apply_immediately = true on the instance.
  parameter {
    name         = "rds.logical_replication"
    value        = "1"
    apply_method = "pending-reboot"
  }

  tags = { Name = "${var.name}-app-postgres16" }
}

# Ephemeral + write-only: the password is generated, handed to Secrets Manager
# and to RDS, and never written to Terraform state in readable form.
#
# The sharp edge: an ephemeral resource is re-evaluated on every plan and
# apply, so `result` is a *different* password each run. Two write-only
# arguments consuming it only agree when both are written in the same apply —
# and a write-only argument is only re-sent when its companion `_wo_version`
# changes.
#
# So if an apply writes the secret and then fails before creating the
# database (an invalid engine version will do it), the next apply generates a
# fresh password, creates the database with it, and leaves the secret holding
# the *first* password forever, because version 1 was already applied.
# Nothing drifts in state; the two values are simply, permanently, different
# — and it surfaces much later as `password authentication failed`.
#
# Both write-only arguments therefore share the ONE var.db_password_version.
# Bumping it rewrites the database password and the secret together, from one
# evaluation, in one apply. That variable is also the recovery lever: any
# partially-failed apply in this file is healed by bumping it.
ephemeral "random_password" "master" {
  length = 32
  # RDS rejects several punctuation characters in master passwords, and a DSN
  # has its own opinions about the rest. 32 alphanumerics is ample entropy
  # without the escaping.
  special = false
}

resource "aws_db_instance" "this" {
  identifier = "${var.name}-app"

  engine = "postgres"
  # Pinned to a concrete minor, with auto-upgrade off so the pin stays
  # truthful — auto_minor_version_upgrade lets AWS move the minor behind
  # Terraform's back, and every later plan then shows a spurious downgrade.
  # Bump deliberately. The platform floor is PostgreSQL >= 14, which is why
  # the version is hardcoded here instead of dangling as a variable someone
  # can lower. RDS retires minors aggressively — when CreateDBInstance
  # rejects the pin, pick the newest from:
  #   aws rds describe-db-engine-versions --engine postgres \
  #     --query "DBEngineVersions[?starts_with(EngineVersion, '16.')].EngineVersion"
  engine_version             = "16.14"
  auto_minor_version_upgrade = false

  instance_class = var.db_instance_class
  multi_az       = var.db_multi_az

  # 100 GiB gp3 is far beyond what the platform writes; the headroom buys the gp3
  # baseline 3000 IOPS without provisioning games. Storage autoscaling to 500
  # is a backstop, not a plan.
  allocated_storage     = 100
  max_allocated_storage = 500
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  username = "postgres"

  # See the ephemeral block's comment: this and the Secrets Manager mirror
  # below MUST share var.db_password_version.
  password_wo         = ephemeral.random_password.master.result
  password_wo_version = var.db_password_version

  # No initial database on purpose: the workloads bootstrap job creates the
  # per-service databases and roles from the master secret, so their existence
  # is evidence the bootstrap ran, not an accident of provisioning.

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.postgres16.name

  # Automated snapshots of a CMK-encrypted instance are encrypted under the
  # same CMK — encrypted backups fall out of storage_encrypted + kms_key_id
  # above with no further configuration. 7 days of retention is the
  # default.
  backup_retention_period = 7

  # See the file header for why there is no prevent_destroy. A leftover final
  # snapshot with this identifier must be removed before a second destroy.
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = !var.deletion_protection
  final_snapshot_identifier = "${var.name}-postgres-final"
  apply_immediately         = true

  tags = { Name = "${var.name}-app" }
}

resource "aws_secretsmanager_secret" "master" {
  name = "${var.name}/app/master"
  # The platform CMK, here and on every secret below. Omitted, Secrets
  # Manager falls back to the AWS-managed aws/secretsmanager key — which
  # would leave the bootstrap role's CMK-Decrypt grant dead code and put
  # these secrets outside the CMK-everywhere posture.
  kms_key_id = var.kms_key_arn
  # Evaluation posture allows immediate re-create after destroy: a recovery
  # window makes every destroy/apply cycle fail on name collision.
  recovery_window_in_days = var.deletion_protection ? 7 : 0

  tags = { Name = "${var.name}-app-master" }
}

# The master secret is a JSON document carrying connection material, not just
# the password, so the bootstrap job needs exactly one secret read to reach
# the database. host/port come from the instance, which makes this version
# depend on the instance — and that is acyclic, not circular: the instance
# takes its password from the ephemeral resource directly and never reads
# this secret, while this secret reads the instance's address. The dependency
# arrow points one way.
#
# The ordering it forces (instance first, ~10 minutes, then this write) does
# widen the partial-apply window the ephemeral-password comment above
# describes. The recovery is the same single lever: bump
# var.db_password_version and apply once.
resource "aws_secretsmanager_secret_version" "master" {
  secret_id = aws_secretsmanager_secret.master.id

  secret_string_wo = jsonencode({
    username = aws_db_instance.this.username
    password = ephemeral.random_password.master.result
    host     = aws_db_instance.this.address
    port     = aws_db_instance.this.port
  })
  secret_string_wo_version = var.db_password_version
}

# --- App secrets (opaque generated strings) ----------------------------------

# Same ephemeral + write-only discipline as the master password, same shared
# version variable, same recovery lever. Values are plain strings, not JSON —
# the KOTS ConfigValues and the bootstrap job consume them verbatim.
ephemeral "random_password" "app" {
  for_each = local.app_secret_names

  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "app" {
  for_each = local.app_secret_names

  name       = "${var.name}/app/${each.value}"
  kms_key_id = var.kms_key_arn
  # See master above.
  recovery_window_in_days = var.deletion_protection ? 7 : 0

  tags = { Name = "${var.name}-app-${each.value}" }
}

resource "aws_secretsmanager_secret_version" "app" {
  for_each = local.app_secret_names

  secret_id                = aws_secretsmanager_secret.app[each.key].id
  secret_string_wo         = ephemeral.random_password.app[each.key].result
  secret_string_wo_version = var.db_password_version
}

# --- ElastiCache Redis -------------------------------------------------------

# THE exception to the write-only pattern, fenced here on purpose:
# aws_elasticache_replication_group.auth_token is a regular argument — the
# provider offers no auth_token_wo — so the value that feeds it must come
# from a state-resident random_password. This is the one place in the deployment
# where a secret exists in Terraform state in recoverable form (marked
# sensitive, but present). Accepted and contained: the state bucket is
# private, encrypted, and lives in the deployment's own account.
#
# The keepers tie means the one rotation lever still works: bumping
# var.db_password_version regenerates this password, updates the replication
# group's token in place (ROTATE strategy below), and rewrites the Secrets
# Manager mirror — all in the same apply as every write-only secret.
resource "random_password" "redis_auth" {
  length = 32
  # ElastiCache rejects '@', '"', '/', and spaces in auth tokens, and a
  # too-clever override_special is exactly how a token gets rejected at apply
  # time after the replication group has already started building.
  # Alphanumeric sidesteps the whole constraint.
  special = false

  keepers = {
    rotation = tostring(var.db_password_version)
  }
}

resource "aws_secretsmanager_secret" "redis_auth" {
  name       = "${var.name}/app/redis-auth"
  kms_key_id = var.kms_key_arn
  # See master above.
  recovery_window_in_days = var.deletion_protection ? 7 : 0

  tags = { Name = "${var.name}-app-redis-auth" }
}

resource "aws_secretsmanager_secret_version" "redis_auth" {
  secret_id                = aws_secretsmanager_secret.redis_auth.id
  secret_string_wo         = random_password.redis_auth.result
  secret_string_wo_version = var.db_password_version
}

resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.name}-app"
  subnet_ids = var.private_subnet_ids

  tags = { Name = "${var.name}-app" }
}

resource "aws_security_group" "redis" {
  name        = "${var.name}-redis"
  description = "Redis from EKS worker nodes only"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-redis" }
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_nodes" {
  description                  = "Redis from EKS worker nodes"
  security_group_id            = aws_security_group.redis.id
  referenced_security_group_id = var.node_security_group_id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
}

# Unrestricted egress for the same reason as the RDS SG above.
resource "aws_vpc_security_group_egress_rule" "redis_all" {
  description       = "Engine-initiated outbound (maintenance, telemetry)"
  security_group_id = aws_security_group.redis.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.name}-app"
  description          = "${var.name} app cache"

  engine         = "redis"
  engine_version = "7.1"
  node_type      = var.redis_node_type
  port           = 6379

  # Cluster mode stays off (the platform speaks single-endpoint Redis), so
  # the stock parameter group is correct and a custom one would only be a
  # blank page to maintain.
  parameter_group_name = "default.redis7"

  # One toggle drives all three: a replica only earns its cost if failover is
  # automatic, and automatic failover requires a second cache cluster. The
  # default is a single node; production flips var.redis_multi_az.
  num_cache_clusters         = var.redis_multi_az ? 2 : 1
  automatic_failover_enabled = var.redis_multi_az
  multi_az_enabled           = var.redis_multi_az

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.redis.id]

  at_rest_encryption_enabled = true
  kms_key_id                 = var.kms_key_arn
  transit_encryption_enabled = true

  auth_token = random_password.redis_auth.result
  # ROTATE keeps both old and new tokens valid during a rotation, so bumping
  # db_password_version doesn't drop live connections mid-apply.
  auth_token_update_strategy = "ROTATE"

  # Lab: maintenance-window queueing would just make plans look like no-ops.
  apply_immediately = true

  tags = { Name = "${var.name}-app" }
}
