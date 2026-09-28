# ElastiCache Redis 7 (replication group) in the data subnets: TLS in transit, KMS at rest,
# AUTH token stored in Secrets Manager and injected into tasks by ECS.
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 6.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

resource "aws_elasticache_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.subnet_ids
}

resource "aws_security_group" "this" {
  name        = "${var.name}-redis"
  description = "Redis from settle services only"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-redis" }
}

resource "aws_vpc_security_group_ingress_rule" "clients" {
  for_each                     = toset(var.client_security_group_ids)
  security_group_id            = aws_security_group.this.id
  description                  = "Redis from ${each.key}"
  referenced_security_group_id = each.key
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
}

# Stored in state (state bucket is KMS-encrypted and access-restricted); moving to
# ElastiCache IAM authentication removes this secret entirely (docs/NOT-DONE.md).
resource "random_password" "auth" {
  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "auth" {
  #checkov:skip=CKV2_AWS_57:Rotating the AUTH token needs a coordinated ElastiCache ROTATE update + task restart; runbook-driven for now, automation in docs/NOT-DONE.md.
  name                    = "${var.name}/redis-auth"
  description             = "AUTH token for settle Redis"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "auth" {
  secret_id     = aws_secretsmanager_secret.auth.id
  secret_string = random_password.auth.result
}

# The queue must never be silently evicted under memory pressure (lost settlement jobs):
# noeviction makes Redis reject writes instead, which the API turns into a 503.
resource "aws_elasticache_parameter_group" "this" {
  name   = "${var.name}-redis7"
  family = "redis7"
  parameter {
    name  = "maxmemory-policy"
    value = "noeviction"
  }
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id       = var.name
  description                = "settle job queue"
  engine                     = "redis"
  engine_version             = "7.1"
  node_type                  = var.node_type
  num_cache_clusters         = var.replicas + 1
  automatic_failover_enabled = var.multi_az
  multi_az_enabled           = var.multi_az
  port                       = 6379
  parameter_group_name       = aws_elasticache_parameter_group.this.name
  subnet_group_name          = aws_elasticache_subnet_group.this.name
  security_group_ids         = [aws_security_group.this.id]
  at_rest_encryption_enabled = true
  kms_key_id                 = var.kms_key_arn
  transit_encryption_enabled = true
  auth_token                 = random_password.auth.result
  snapshot_retention_limit   = var.snapshot_retention_days
  auto_minor_version_upgrade = true
  apply_immediately          = false
}
