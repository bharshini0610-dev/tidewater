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
    tags = { project = "settle", environment = "prod", managed-by = "terraform" }
  }
}

module "settle" {
  source = "../../modules/settle"

  environment     = "prod"
  app_version     = var.app_version
  image           = var.image
  certificate_arn = var.certificate_arn
  bank_url        = var.bank_url

  vpc_cidr                   = "10.50.0.0/16"
  single_nat_gateway         = false # NAT per AZ: an AZ outage does not cut egress
  enable_interface_endpoints = true
  deletion_protection        = true
  log_retention_days         = 365

  api_cpu          = 1024
  api_memory       = 2048
  api_min_count    = 3
  api_max_count    = 6
  worker_min_count = 2
  worker_max_count = 2

  db_instance_class        = "db.m7g.large"
  db_storage_gb            = 100
  db_multi_az              = true
  db_backup_retention_days = 14
  db_performance_insights  = true
  db_monitoring_interval   = 60

  redis_node_type = "cache.m7g.large"
  redis_replicas  = 1
  redis_multi_az  = true
}

