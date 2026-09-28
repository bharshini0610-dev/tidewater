# The whole settle stack for one environment. envs/staging and envs/prod call this module
# with different sizes; nothing is copy-pasted between environments.
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 6.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  name = "settle-${var.environment}"
  # Connection budget on AWS (RDS max_connections = var.db_max_connections), see docs/CHANGES.md:
  #   api    : ceil(api_max * deploy_max%) tasks x 4 gunicorn workers x pool 2
  #   worker : ceil(worker_max * 2)       tasks x 1 process          x pool 2
  #   + migrations 1 + rds_superuser reserved 3 + admin headroom 10
  api_peak_tasks    = ceil(var.api_max_count * var.api_deployment_maximum_percent / 100)
  worker_peak_tasks = var.worker_max_count * 2
  db_budget         = local.api_peak_tasks * 4 * 2 + local.worker_peak_tasks * 2 + 1 + 3 + 10
  app_env = {
    APP_VERSION                    = var.app_version
    LOG_LEVEL                      = "INFO"
    GUNICORN_WORKERS               = "4"
    DB_POOL_SIZE                   = "2"
    DB_MAX_OVERFLOW                = "0"
    DB_POOL_TIMEOUT_S              = "2"
    DB_STATEMENT_TIMEOUT_MS        = "5000"
    DB_REPORT_STATEMENT_TIMEOUT_MS = "15000"
    DB_HOST                        = module.database.address
    DB_NAME                        = "settle"
    DB_SSLMODE                     = "require"
    REDIS_HOST                     = module.cache.primary_endpoint
    REDIS_TLS                      = "true"
    BANK_URL                       = var.bank_url
  }
  app_secrets = {
    DB_USER     = "${module.database.master_user_secret_arn}:username::"
    DB_PASSWORD = "${module.database.master_user_secret_arn}:password::"
    REDIS_AUTH  = module.cache.auth_secret_arn
  }
  secret_arns = [module.database.master_user_secret_arn, module.cache.auth_secret_arn]
}

check "db_connection_budget" {
  assert {
    condition     = local.db_budget <= var.db_max_connections
    error_message = "Peak connections (${local.db_budget}) exceed max_connections (${var.db_max_connections}); lower max counts or add PgBouncer/RDS Proxy."
  }
}

# One customer-managed key for this environment's data (RDS, Redis, secrets, logs).
resource "aws_kms_key" "this" {
  description         = "${local.name} data"
  enable_key_rotation = true
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountAdmin"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "CloudWatchLogs"
        Effect    = "Allow"
        Principal = { Service = "logs.${data.aws_region.current.region}.amazonaws.com" }
        Action    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
        Resource  = "*"
        Condition = {
          ArnLike = { "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:*" }
        }
      }
    ]
  })
}

resource "aws_kms_alias" "this" {
  name          = "alias/${local.name}"
  target_key_id = aws_kms_key.this.key_id
}

module "network" {
  source                     = "../network"
  name                       = local.name
  cidr_block                 = var.vpc_cidr
  availability_zones         = ["${data.aws_region.current.region}a", "${data.aws_region.current.region}b"]
  single_nat_gateway         = var.single_nat_gateway
  enable_interface_endpoints = var.enable_interface_endpoints
  kms_key_arn                = aws_kms_key.this.arn
  log_retention_days         = var.log_retention_days
}

resource "aws_ecr_repository" "api" {
  name                 = "settle-api-${var.environment}"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.this.arn
  }
}

resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "keep the last 30 images (rollback targets)"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 30 }
      action       = { type = "expire" }
    }]
  })
}

resource "aws_ecs_cluster" "this" {
  name = local.name
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

module "alb" {
  source               = "../alb"
  name                 = local.name
  vpc_id               = module.network.vpc_id
  vpc_cidr             = var.vpc_cidr
  public_subnet_ids    = module.network.public_subnet_ids
  certificate_arn      = var.certificate_arn
  allowed_ingress_cidr = var.allowed_ingress_cidr
  deletion_protection  = var.deletion_protection
  kms_key_arn          = aws_kms_key.this.arn
  log_retention_days   = var.log_retention_days
  waf_rate_limit       = var.waf_rate_limit_per_5min
}

module "api" {
  source                     = "../ecs-service"
  name                       = "${local.name}-api"
  cluster_arn                = aws_ecs_cluster.this.arn
  cluster_name               = aws_ecs_cluster.this.name
  image                      = var.image
  cpu                        = var.api_cpu
  memory                     = var.api_memory
  min_count                  = var.api_min_count
  max_count                  = var.api_max_count
  deployment_maximum_percent = var.api_deployment_maximum_percent
  vpc_id                     = module.network.vpc_id
  vpc_cidr                   = var.vpc_cidr
  subnet_ids                 = module.network.app_subnet_ids
  container_port             = 8000
  target_group_arn           = module.alb.target_group_arn
  alb_security_group_id      = module.alb.security_group_id
  environment                = local.app_env
  secrets                    = local.app_secrets
  secret_arns                = local.secret_arns
  kms_key_arn                = aws_kms_key.this.arn
  stop_timeout               = 45
  health_check_command       = ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/livez', timeout=3)"]
  deployment_alarm_names     = [module.alb.deployment_alarm_name]
  log_retention_days         = var.log_retention_days
}

module "worker" {
  source             = "../ecs-service"
  name               = "${local.name}-worker"
  cluster_arn        = aws_ecs_cluster.this.arn
  cluster_name       = aws_ecs_cluster.this.name
  image              = var.image
  command            = ["python", "-m", "settle.worker"]
  cpu                = 256
  memory             = 512
  min_count          = var.worker_min_count
  max_count          = var.worker_max_count
  vpc_id             = module.network.vpc_id
  vpc_cidr           = var.vpc_cidr
  subnet_ids         = module.network.app_subnet_ids
  environment        = merge(local.app_env, { PROMETHEUS_MULTIPROC_DIR = "" })
  secrets            = local.app_secrets
  secret_arns        = local.secret_arns
  kms_key_arn        = aws_kms_key.this.arn
  stop_timeout       = 90 # SIGTERM drain: finish the in-flight payout
  log_retention_days = var.log_retention_days
}

module "database" {
  source                       = "../database"
  name                         = local.name
  vpc_id                       = module.network.vpc_id
  subnet_ids                   = module.network.data_subnet_ids
  client_security_group_ids    = [module.api.security_group_id, module.worker.security_group_id]
  kms_key_arn                  = aws_kms_key.this.arn
  instance_class               = var.db_instance_class
  allocated_storage_gb         = var.db_storage_gb
  multi_az                     = var.db_multi_az
  deletion_protection          = var.deletion_protection
  backup_retention_days        = var.db_backup_retention_days
  max_connections              = var.db_max_connections
  performance_insights_enabled = var.db_performance_insights
  monitoring_interval          = var.db_monitoring_interval
}

module "cache" {
  source                    = "../cache"
  name                      = local.name
  vpc_id                    = module.network.vpc_id
  subnet_ids                = module.network.data_subnet_ids
  client_security_group_ids = [module.api.security_group_id, module.worker.security_group_id]
  kms_key_arn               = aws_kms_key.this.arn
  node_type                 = var.redis_node_type
  replicas                  = var.redis_replicas
  multi_az                  = var.redis_multi_az
}

