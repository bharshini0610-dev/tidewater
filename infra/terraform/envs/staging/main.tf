terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

# Credentials come from the environment (SSO / OIDC role in CI) — never from code.
provider "aws" {
  region = var.region
  default_tags {
    tags = { project = "settle", environment = "staging", managed-by = "terraform" }
  }
}

# Staging: sized to stay under USD 250/month (estimate in infra/terraform/COST.md).
module "settle" {
  source = "../../modules/settle"

  environment     = "staging"
  app_version     = var.app_version
  image           = var.image
  certificate_arn = var.certificate_arn
  bank_url        = var.bank_url

  vpc_cidr                   = "10.40.0.0/16"
  single_nat_gateway         = true  # one NAT instead of two (-USD 35)
  enable_interface_endpoints = false # 4 endpoints x 2 AZ would cost ~USD 64
  deletion_protection        = false
  log_retention_days         = 30

  api_cpu          = 512
  api_memory       = 1024
  api_min_count    = 2
  api_max_count    = 4
  worker_min_count = 1
  worker_max_count = 2

  db_instance_class        = "db.t4g.small"
  db_storage_gb            = 20
  db_multi_az              = false # staging tolerates an AZ outage
  db_backup_retention_days = 7
  db_performance_insights  = false # not available on t4g.small
  db_monitoring_interval   = 0

  redis_node_type = "cache.t4g.micro"
  redis_replicas  = 0
  redis_multi_az  = false
}

