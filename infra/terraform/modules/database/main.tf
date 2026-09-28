# RDS PostgreSQL 15 in the data subnets. Only the ECS service security groups can reach
# it. The master password is generated and rotated by RDS in Secrets Manager
# (manage_master_user_password) — it never appears in Terraform code, tfvars or state.
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.subnet_ids
}

resource "aws_security_group" "this" {
  name        = "${var.name}-rds"
  description = "Postgres from settle services only"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-rds" }
}

resource "aws_vpc_security_group_ingress_rule" "clients" {
  for_each                     = toset(var.client_security_group_ids)
  security_group_id            = aws_security_group.this.id
  description                  = "Postgres from ${each.key}"
  referenced_security_group_id = each.key
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_db_parameter_group" "this" {
  name   = "${var.name}-pg15"
  family = "postgres15"

  # Must match the application connection budget (docs/CHANGES.md). Static -> reboot.
  parameter {
    name         = "max_connections"
    value        = tostring(var.max_connections)
    apply_method = "pending-reboot"
  }
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }
  parameter {
    name  = "idle_in_transaction_session_timeout"
    value = "10000"
  }
  parameter {
    name  = "log_lock_waits"
    value = "1"
  }
}

resource "aws_iam_role" "monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0
  name  = "${var.name}-rds-monitoring"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  count      = var.monitoring_interval > 0 ? 1 : 0
  role       = aws_iam_role.monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_db_instance" "this" {
  identifier     = var.name
  engine         = "postgres"
  engine_version = "15"
  instance_class = var.instance_class
  db_name        = "settle"
  username       = "settle_admin"
  port           = 5432

  manage_master_user_password   = true
  master_user_secret_kms_key_id = var.kms_key_arn

  allocated_storage     = var.allocated_storage_gb
  max_allocated_storage = var.allocated_storage_gb * 4
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false
  multi_az               = var.multi_az

  backup_retention_period   = var.backup_retention_days
  backup_window             = "02:00-03:00"
  maintenance_window        = "sun:03:30-sun:04:30"
  copy_tags_to_snapshot     = true
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name}-final"

  iam_database_authentication_enabled   = true
  auto_minor_version_upgrade            = true
  enabled_cloudwatch_logs_exports       = ["postgresql", "upgrade"]
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_kms_key_id       = var.performance_insights_enabled ? var.kms_key_arn : null
  performance_insights_retention_period = var.performance_insights_enabled ? 7 : null
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = var.monitoring_interval > 0 ? aws_iam_role.monitoring[0].arn : null
  apply_immediately                     = false
}
