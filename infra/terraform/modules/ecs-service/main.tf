# One Fargate service (used for both settle-api and settle-worker).
# * image is always an immutable digest (ECR repo has IMMUTABLE tags)
# * secrets are injected by ECS from Secrets Manager at task start (never in env/tfvars/image)
# * execution role can read exactly the listed secrets; task role has no permissions
# * deployment circuit breaker + CloudWatch alarm => automatic rollback
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

data "aws_region" "current" {}

locals {
  is_http = var.container_port != null
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/settle/${var.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

# --- IAM ------------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.name}-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "read_secrets" {
  statement {
    sid       = "ReadOnlyTheseSecrets"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = var.secret_arns
  }
  statement {
    sid       = "DecryptThem"
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "read_secrets" {
  name   = "read-settle-secrets"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.read_secrets.json
}

# The application itself calls no AWS APIs: its task role grants nothing.
resource "aws_iam_role" "task" {
  name               = "${var.name}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

# --- network --------------------------------------------------------------------------
resource "aws_security_group" "this" {
  name        = "${var.name}-svc"
  description = "settle ${var.name} tasks"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-svc" }
}

resource "aws_vpc_security_group_ingress_rule" "from_alb" {
  count                        = local.is_http ? 1 : 0
  security_group_id            = aws_security_group.this.id
  description                  = "HTTP from the ALB only"
  referenced_security_group_id = var.alb_security_group_id
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "in_vpc" {
  for_each          = toset(["5432", "6379", "443"])
  security_group_id = aws_security_group.this.id
  description       = "To RDS/ElastiCache/VPC endpoints inside the VPC"
  cidr_ipv4         = var.vpc_cidr
  from_port         = tonumber(each.key)
  to_port           = tonumber(each.key)
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "https_out" {
  security_group_id = aws_security_group.this.id
  description       = "HTTPS to the bank API and AWS public endpoints via NAT"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# --- task + service -------------------------------------------------------------------
resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
  volume {
    name = "tmp"
  }
  container_definitions = jsonencode([{
    name                   = var.name
    image                  = var.image
    essential              = true
    command                = var.command
    user                   = "10001:10001"
    readonlyRootFilesystem = true
    stopTimeout            = var.stop_timeout
    linuxParameters        = { initProcessEnabled = true }
    portMappings           = local.is_http ? [{ containerPort = var.container_port, protocol = "tcp" }] : []
    environment            = [for k, v in var.environment : { name = k, value = v }]
    secrets                = [for k, v in var.secrets : { name = k, valueFrom = v }]
    mountPoints            = [{ sourceVolume = "tmp", containerPath = "/tmp", readOnly = false }]
    healthCheck = var.health_check_command == null ? null : {
      command     = var.health_check_command
      interval    = 15
      timeout     = 5
      retries     = 4
      startPeriod = 20
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.this.name
        awslogs-region        = data.aws_region.current.region
        awslogs-stream-prefix = var.name
      }
    }
  }])
}

resource "aws_ecs_service" "this" {
  name                               = var.name
  cluster                            = var.cluster_arn
  task_definition                    = aws_ecs_task_definition.this.arn
  desired_count                      = var.min_count
  launch_type                        = "FARGATE"
  platform_version                   = "LATEST"
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = var.deployment_maximum_percent
  health_check_grace_period_seconds  = local.is_http ? 30 : null
  enable_execute_command             = false
  propagate_tags                     = "SERVICE"

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  dynamic "alarms" {
    for_each = length(var.deployment_alarm_names) > 0 ? [1] : []
    content {
      alarm_names = var.deployment_alarm_names
      enable      = true
      rollback    = true
    }
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.this.id]
    assign_public_ip = false
  }

  dynamic "load_balancer" {
    for_each = local.is_http ? [1] : []
    content {
      target_group_arn = var.target_group_arn
      container_name   = var.name
      container_port   = var.container_port
    }
  }

  lifecycle {
    ignore_changes = [desired_count] # owned by autoscaling
  }
}

# max_count is bounded by the DB connection budget, not by CPU (docs/CHANGES.md).
resource "aws_appautoscaling_target" "this" {
  service_namespace  = "ecs"
  resource_id        = "service/${var.cluster_name}/${aws_ecs_service.this.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.min_count
  max_capacity       = var.max_count
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.name}-cpu"
  service_namespace  = aws_appautoscaling_target.this.service_namespace
  resource_id        = aws_appautoscaling_target.this.resource_id
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension
  policy_type        = "TargetTrackingScaling"
  target_tracking_scaling_policy_configuration {
    target_value       = 70
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
