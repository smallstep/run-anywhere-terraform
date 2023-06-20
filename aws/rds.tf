#----------------------------------------------------------------------------------
#
# This file is where we set up Amazon all RDS databases and related resources
#
#----------------------------------------------------------------------------------
# There are 10 PostgreSQL databases being set up. These are defined in locals.
#----------------------------------------------------------------------------------

locals {
  # list of all database names needed
  # will not need to change

  cw_logging_value = var.rds_enable_cloudwatch_logging == true ? ["postgresql"] : [""]

  # All information needed to log into a database cluster
  # Will be stored in SecretsManager
  master_creds = {
    host     = aws_rds_cluster.smallstep.endpoint
    username = var.rds_master_username
    password = random_password.initial_master_password.result
    port     = var.rds_port
  }

  rds_default_params = var.rds_enable_cloudwatch_logging == true ? local.rds_logging_params : local.rds_non_logging_params

  # If we're going to set up logs for Aurora, the following are what we need to make sure everything works
  rds_logging_params = [
    {
      name  = "idle_in_transaction_session_timeout"
      value = "${var.rds_transaction_timeout}"
    },
    {
      name  = "auto_explain.log_analyze"
      value = "1"
    },
    {
      name  = "auto_explain.log_verbose"
      value = "1"
    },
    {
      name  = "log_connections"
      value = "1"
    },
    {
      name  = "log_disconnections"
      value = "1"
    },
    {
      name  = "rds.log_retention_period"
      value = "${var.backup_retention_period}" * 1440
    }
  ]

  rds_non_logging_params = [{
    name  = "idle_in_transaction_session_timeout"
    value = "${var.rds_transaction_timeout}"
  }]
}

# Set up the SG assigned to each db with a base set of recommended ICMP rules
module "rds_base_security_group_rules" {
  source            = "./base_security_group_rules"
  security_group_id = aws_security_group.rds.id
  vpc               = var.vpc
}

resource "aws_db_parameter_group" "smallstep" {
  name   = var.default_name
  family = "aurora-postgresql${split(".", var.rds_engine_version)[0]}"

  # parameters = concat(local.rds_default_params, var.rds_desired_params)
  # parameters = local.rds_default_params
  dynamic "parameter" {
    for_each = concat(local.rds_default_params, var.rds_desired_params)
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = lookup(parameter.value, "apply_method", null)
    }
  }
}

# Create one Aurora cluster and create each of the 10 required databases using Lambda.
resource "aws_rds_cluster" "smallstep" {
  apply_immediately         = true
  availability_zones        = data.aws_availability_zones.available.names
  backup_retention_period   = var.backup_retention_period
  cluster_identifier        = var.default_name
  copy_tags_to_snapshot     = true
  deletion_protection       = true
  engine                    = "aurora-postgresql"
  engine_mode               = "provisioned"
  engine_version            = var.rds_engine_version
  final_snapshot_identifier = "${var.default_name}-final"
  storage_encrypted         = true
  kms_key_id                = aws_kms_key.smallstep.arn
  port                      = var.rds_port

  # The master username/password are also stored in SecretsManager
  master_password = random_password.initial_master_password.result
  master_username = var.rds_master_username

  # Backup in case the database is destroyed
  skip_final_snapshot    = false
  vpc_security_group_ids = [aws_security_group.rds.id]

  # Export logs to CW
  enabled_cloudwatch_logs_exports = local.cw_logging_value

  tags = {
    Name        = var.default_name
    Description = var.default_description
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_rds_cluster_instance" "smallstep" {
  count = var.rds_instance_count

  identifier                      = "${var.default_name}-${format("%02d", count.index + 1)}"
  cluster_identifier              = aws_rds_cluster.smallstep.cluster_identifier
  engine                          = "aurora-postgresql"
  instance_class                  = var.rds_instance_class
  publicly_accessible             = false
  apply_immediately               = true
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.smallstep.arn

  # Making the first db the preferred writer for QoL reasons
  promotion_tier = count.index

  # Please tune this group to suit your needs
  db_parameter_group_name = aws_db_parameter_group.smallstep.name

  tags = {
    Name        = "${var.default_name}-${format("%02d", count.index + 1)}"
    Description = var.default_description
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Security Group for the DBs
resource "aws_security_group" "rds" {
  name        = "${var.default_name}-postgres-dbs"
  vpc_id      = var.vpc
  description = var.default_description

  tags = {
    Name        = "${var.default_name}-postgres-dbs"
    Description = var.default_description
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Allow ingress from the EKS cluster only on the given port
resource "aws_security_group_rule" "eks_to_rds" {
  type                     = "ingress"
  from_port                = var.rds_port
  to_port                  = var.rds_port
  protocol                 = "tcp"
  source_security_group_id = aws_eks_cluster.eks.vpc_config[0].cluster_security_group_id
  security_group_id        = aws_security_group.rds.id
  description              = "Allow ingress from the EKS cluster running in the smallstep project"

  lifecycle {
    create_before_destroy = true
  }
}

# Allow for clustering and lambda access
resource "aws_security_group_rule" "rds_to_rds" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rds.id
  security_group_id        = aws_security_group.rds.id
  description              = "Allow for database clustering"

  lifecycle {
    create_before_destroy = true
  }
}

