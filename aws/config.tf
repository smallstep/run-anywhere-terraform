#---------------------------------------------------------------------------------- 
# 
# This file funtions as the source of high-level `data`, `local`, and `variable`
# resource types for the AWS Onprem Terraform Project.
# 
#----------------------------------------------------------------------------------

locals {
  # Number of days to keep backups/resources after deletion
  backup_retention_period            = 7

  # the base domain for all smallstep subdomains
  base_domain                        = "replicated.awsdev.smallstep.com"

  # Naming convention used through the whole project
  default_description                = "Terraform - Do not modify by hand."
  default_name                       = "run-anywhere-terraform"

  # If you are setting up your deployment to use a YubiHSM2, enable this flag
  hsm_enabled                        = true

  # AWS region
  region                             = "us-west-1"

  # ID list of at least 2 of the subnets you're deploying these resources to
  # Must be in different AZs and behind a NAT gateway
  subnets_private                    = ["subnet-0375e8740c23d7b10", "subnet-05f929cf38ed493ef"]

  # ID list of at least 2 public subnets to deploy an NLB
  # Must be the same number of subnets as subnets_private
  subnets_public                     = ["subnet-d799f8b3", "subnet-6593223d"]                    

  k8s_configs = {
    # node types desired for kubernetes nodes
    # https://aws.amazon.com/ec2/instance-types/
    instance_types   = ["t3.large"]

    # kube config path
    kube_config_path = "~/.kube/config"

    # kubernetes namespace where smallstep will be installed
    namespace        = "smallstep"

    # node pool autoscaling settings
    pool_desired     = 8
    pool_max         = 10
    pool_min         = 3
  }

  redis_configs = {
    # number of clusters used for caching
    cache_clusters   = 2

    # desired redis engine
    engine_version   = "5.0.6"

    # desired version of redis
    # Permitted values: redis4.0, redis5.0
    family           = "redis5.0"

    # Permitted values: allkeys-lru, volatile-lru, allkeys-lfu, volatile-lfu, allkeys-random, volatile-random, noeviction
    max_memory       = "volatile-lru"

    # size/power of the nodes used to run redis
    node_type        = "cache.m5.large"

    # entrypoint port for redis
    port             = 6379

    time_out         = 300
  }

  rds_configs = {
    # desired postgres aurora versioin for all associated postgresql databases
    engine_version       = "13.4"

    # number of desired db instances in the cluster
    # if >1 then there will be assigned readers
    instance_count       = 2

    # Assuring compatibility with engine_version, set the instance class according to:
    # https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.DBInstanceClass.html
    instance_class       = "db.r6g.large"

    # username for all associated databases
    master_username      = "master"

    # entrypoint port for each database
    port                 = 5432

    # min/max number of db nodes that can run
    max_capacity         = 8
    min_capacity         = 2
  }
}
