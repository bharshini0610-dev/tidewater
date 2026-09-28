variable "environment" {
  type = string
}

variable "app_version" {
  type = string
}

variable "image" {
  description = "settle-api image pinned by digest; the pipeline promotes the same digest staging -> prod"
  type        = string
}

variable "certificate_arn" {
  type = string
}

variable "bank_url" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "single_nat_gateway" {
  type = bool
}

variable "enable_interface_endpoints" {
  type = bool
}

variable "allowed_ingress_cidr" {
  type    = string
  default = "0.0.0.0/0"
}

variable "waf_rate_limit_per_5min" {
  description = "Requests per 5 minutes per client IP before WAF blocks"
  type        = number
  default     = 3000
}

variable "deletion_protection" {
  type = bool
}

variable "log_retention_days" {
  type = number
}

variable "api_cpu" {
  type = number
}

variable "api_memory" {
  type = number
}

variable "api_min_count" {
  type = number
}

variable "api_max_count" {
  type = number
}

variable "api_deployment_maximum_percent" {
  type    = number
  default = 150
}

variable "worker_min_count" {
  type = number
}

variable "worker_max_count" {
  type = number
}

variable "db_instance_class" {
  type = string
}

variable "db_storage_gb" {
  type = number
}

variable "db_multi_az" {
  type = bool
}

variable "db_backup_retention_days" {
  type = number
}

variable "db_max_connections" {
  type    = number
  default = 100
}

variable "db_performance_insights" {
  type = bool
}

variable "db_monitoring_interval" {
  type = number
}

variable "redis_node_type" {
  type = string
}

variable "redis_replicas" {
  type = number
}

variable "redis_multi_az" {
  type = bool
}
