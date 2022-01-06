#----------------------------------------------------------------------------------
# 
# This file is where we set up Amazon all RDS databases and related resources
# 
#----------------------------------------------------------------------------------
# There are 10 PostgreSQL databases being set up. These are defined in locals.
#----------------------------------------------------------------------------------

data "archive_file" "make_dbs" {
  type        = "zip"
  output_path = "${path.module}/lambda.zip"
  source_dir  = "${path.module}/lambda/"
}

locals {
  # list of all database names needed
  # will not need to change
  db_names         = ["landlord", "certificates", "web", "depot", "folk", "memoir", "majordomo", "moody", "courier"]

  cw_logging_value = var.rds_enable_cloudwatch_logging == true ? ["postgresql"] : [""]

  # All information needed to log into a database cluster
  # Will be stored in SecretsManager
  master_creds = {
    db_names      = local.db_names
    host          = aws_rds_cluster.smallstep.endpoint
    username      = var.rds_master_username
    password      = random_password.initial_master_password.result
    port          = var.rds_port
  }

  rds_default_params = var.rds_enable_cloudwatch_logging == true ? local.rds_logging_params : local.rds_non_logging_params

  # If we're going to set up logs for Aurora, the following are what we need to make sure everything works
  rds_logging_params = [
    {
      name         = "idle_in_transaction_session_timeout"
      value        = "${var.rds_transaction_timeout}"
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
      value = "${var.backup_retention_period} * 1440"
    }
  ]

  rds_non_logging_params = [{
    name         = "idle_in_transaction_session_timeout"
    value        = "${var.rds_transaction_timeout}"
  }]
}

# Set up the SG assigned to each db with a base set of recommended ICMP rules
# If you want to test from the public internet, you can uncomment the `public_facing` line
# Defaults to only allowing these rules internal to the VPC
module "rds_base_security_group_rules" {
  source            = "./base_security_group_rules"
  public_facing     = var.security_groups_public
  security_group_id = aws_security_group.rds.id
}

resource "aws_db_parameter_group" "smallstep" {
  name   = var.default_name
  family = "aurora-postgresql${split(".", var.rds_engine_version)[0]}"

  parameter {concat(local.rds_default_params, var.rds_desired_params)}
}

resource "aws_lambda_function" "make_dbs" {
  filename                       = data.archive_file.make_dbs.output_path
  function_name                   = "${var.default_name}-make-dbs"
  role                           = aws_iam_role.make_dbs.arn
  handler                        = "make_dbs.lambda_handler"
  source_code_hash               = data.archive_file.make_dbs.output_base64sha256
  runtime                        = "python3.8"
  description                    = "Sets up the individual databases in the Aurora cluster - managed by TF do not modify"
  timeout                        = 300
  reserved_concurrent_executions = 1

  vpc_config {
    subnet_ids         = var.subnets_private
    security_group_ids = [aws_security_group.rds.id]
  }

  environment {
    variables = {
      secret_id = aws_secretsmanager_secret.master_password.id
    }
  }

  tags = {
    Name        = "${var.default_name}-make-dbs"
    Description = var.default_description
  }

  depends_on = [
    aws_rds_cluster.smallstep
  ]
}

resource "aws_iam_role" "make_dbs" {
  name = "${var.default_name}-make-dbs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Effect = "Allow"
        Sid = ""
      }
    ]
  })

  description = "Permissions for Lambda function Managed by Terraform do not modify"
}

# Since this Lambda will talk to the database cluster, we must launch it in a VPC.
resource "aws_iam_role_policy_attachment" "make_dbs_1" {
  role       = aws_iam_role.make_dbs.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Grant the lambda rights to our KMS key that we use to encrypt secrets for the project
resource "aws_iam_role_policy" "make_dbs_2" {
  name = "${var.default_name}-kms-decrypt"
  role = aws_iam_role.make_dbs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "kms:Decrypt",
        ]
        Effect   = "Allow"
        Resource = "${aws_kms_key.smallstep.arn}"
      },
    ]
  })
}

# Grant the lambda rights to the SecretsManager secret used to store the cluster login info
resource "aws_iam_role_policy" "make_dbs_3" {
  name = "${var.default_name}-db-secret-access"
  role = aws_iam_role.make_dbs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "secretsmanager:GetSecretValue",
        ]
        Effect   = "Allow"
        Resource = "${aws_secretsmanager_secret.master_password.arn}"
      },
    ]
  })
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
  skip_final_snapshot       = false
  vpc_security_group_ids    = [aws_security_group.rds.id]

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

  identifier          = "${var.default_name}-${format("%02d", count.index + 1)}"
  cluster_identifier  = aws_rds_cluster.smallstep.cluster_identifier
  engine              = "aurora-postgresql"
  instance_class      = var.rds_instance_class
  publicly_accessible = false
  apply_immediately   = true

  # Making the first db the preferred writer for QoL reasons
  promotion_tier      = count.index

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
  vpc_id      = data.aws_subnet.public[0].vpc_id
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
  source_security_group_id = aws_security_group.eks.id
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
  description              = "Allow ingress from the EKS cluster running in the smallstep project"

  lifecycle {
    create_before_destroy = true
  }
}

resource "null_resource" "make_dbs" {
  provisioner "local-exec" {
    command     = "aws lambda invoke --function-name ${aws_lambda_function.make_dbs.arn} /dev/null"
  }

  depends_on = [
    aws_rds_cluster.smallstep,
    aws_rds_cluster_instance.smallstep,
    aws_lambda_function.make_dbs,
    aws_security_group.rds
  ]
}
