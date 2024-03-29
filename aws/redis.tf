#----------------------------------------------------------------------------------
#
# This file is where we set up Amazon ElastiCache for Redis and related resources
#
#----------------------------------------------------------------------------------

locals {
  redis_default_params = [
    {
      name  = "cluster-enabled"
      value = "no"
    },
    {
      name  = "maxmemory-policy"
      value = "${var.redis_max_memory_policy}"
    },
    {
      name  = "timeout"
      value = "${var.redis_timeout}"
    }
  ]
}

# Set up the SG assigned to redis with a base set of recommended ICMP rules
# If you want to test from the public internet, you can uncomment the `public_facing` line
# Defaults to only allowing these rules internal to the VPC
module "redis_base_security_group_rules" {
  source            = "./base_security_group_rules"
  security_group_id = aws_security_group.redis.id
  vpc               = var.vpc
}

# Creates a parameter group for the Redis cluster.
# Since Redis has numerous options we can tune, only set the ones we care about.
# Add additional setting as needed.
resource "aws_elasticache_parameter_group" "redis" {
  name   = var.default_name
  family = var.redis_family

  # parameters = concat(local.redis_default_params, var.redis_desired_params)
  dynamic "parameter" {
    for_each = concat(local.redis_default_params, var.redis_desired_params)
    content {
      name  = parameter.value.name
      value = parameter.value.value
    }
  }
}

# Replication Group will create the underlying redis instances
resource "aws_elasticache_replication_group" "redis" {
  apply_immediately          = true
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  automatic_failover_enabled = var.redis_cache_clusters > 1 ? true : false
  auto_minor_version_upgrade = true
  engine                     = "redis"
  engine_version             = var.redis_engine_version
  node_type                  = var.redis_node_type
  num_cache_clusters         = var.redis_cache_clusters
  parameter_group_name       = aws_elasticache_parameter_group.redis.id
  port                       = var.redis_port
  description                = var.default_description
  replication_group_id       = var.default_name
  subnet_group_name          = aws_elasticache_subnet_group.redis.name
  security_group_ids         = [aws_security_group.redis.id]

  tags = {
    Name      = var.default_name
    ManagedBy = var.default_description
  }
}

resource "aws_elasticache_subnet_group" "redis" {
  name       = var.default_name
  subnet_ids = var.subnets_private
}

resource "aws_security_group" "redis" {
  name        = "${var.default_name}-redis"
  vpc_id      = var.vpc
  description = var.default_description

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name      = "${var.default_name}-redis"
    ManagedBy = var.default_description
  }
}

# Allow ingress from the EKS cluster only on the given port
resource "aws_security_group_rule" "eks_to_redis" {
  type                     = "ingress"
  from_port                = var.redis_port
  to_port                  = var.redis_port
  protocol                 = "tcp"
  source_security_group_id = aws_eks_cluster.eks.vpc_config[0].cluster_security_group_id
  security_group_id        = aws_security_group.redis.id
  description              = "Allow ingress from the EKS cluster running in the smallstep project"

  lifecycle {
    create_before_destroy = true
  }
}
