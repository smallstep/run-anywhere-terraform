#----------------------------------------------------------------------------------
# 
# This file is where we set up Amazon ElastiCache for Redis and related resources
# 
#----------------------------------------------------------------------------------

# Set up the SG assigned to redis with a base set of recommended ICMP rules
# If you want to test from the public internet, you can uncomment the `public_facing` line
# Defaults to only allowing these rules internal to the VPC
module "redis_base_security_group_rules" {
  source            = "./base_security_group_rules"
  security_group_id = aws_security_group.redis.id
}

# Creates a parameter group for the Redis cluster.
# Since Redis has numerous options we can tune, only set the ones we care about.
# Add additional setting as needed.
resource "aws_elasticache_parameter_group" "redis" {
  name   = local.default_name
  family = local.redis_configs.family

  parameter {
    name  = "cluster-enabled"
    value = "no"
  }

  parameter {
    name  = "maxmemory-policy"
    value = local.redis_configs.max_memory
  }

  parameter {
    name  = "timeout"
    value = local.redis_configs.time_out
  }
}

# Replication Group will create the underlying redis instances
resource "aws_elasticache_replication_group" "redis" {
  apply_immediately             = true
  at_rest_encryption_enabled    = true
  automatic_failover_enabled    = local.redis_configs.cache_clusters > 1 ? true : false
  auto_minor_version_upgrade    = true
  engine                        = "redis"
  engine_version                = local.redis_configs.engine_version
  node_type                     = local.redis_configs.node_type
  number_cache_clusters         = local.redis_configs.cache_clusters
  parameter_group_name          = aws_elasticache_parameter_group.redis.id
  port                          = local.redis_configs.port
  replication_group_description = local.default_description
  replication_group_id          = local.default_name
  subnet_group_name             = aws_elasticache_subnet_group.redis.name
  security_group_ids            = [aws_security_group.redis.id]

  tags = {
    Name      = local.default_name
    ManagedBy = local.default_description
  }
}

resource "aws_elasticache_subnet_group" "redis" {
  name       = local.default_name
  subnet_ids = local.subnets_private
}

resource "aws_security_group" "redis" {
  name        = "${local.default_name}-redis"
  vpc_id      = data.aws_subnet.public[0].vpc_id
  description = local.default_description

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name      = "${local.default_name}-redis"
    ManagedBy = local.default_description
  }
}

# TODO: TEST OUT JUST USING THIS SECURITY GROUP EVERYWHERE FOR THE SAKE OF SIMPLICITY
# 
# Allow ingress from the EKS cluster only on the given port
resource "aws_security_group_rule" "eks_to_redis" {
  type                     = "ingress"
  from_port                = local.redis_configs.port
  to_port                  = local.redis_configs.port
  protocol                 = "tcp"
  # source_security_group_id = aws_security_group.eks.id
  source_security_group_id = aws_eks_cluster.eks.vpc_config[0].cluster_security_group_id
  security_group_id        = aws_security_group.redis.id
  description              = "Allow ingress from the EKS cluster running in the smallstep project"

  lifecycle {
    create_before_destroy = true
  }
}