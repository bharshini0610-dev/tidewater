variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "client_security_group_ids" {
  description = "Security groups allowed to connect on 5432 (the ECS services)"
  type        = list(string)
}

variable "kms_key_arn" {
  type = string
}

variable "instance_class" {
  type    = string
  default = "db.m7g.large"
}

variable "allocated_storage_gb" {
  type    = number
  default = 100
}

variable "multi_az" {
  type    = bool
  default = true
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "backup_retention_days" {
  type    = number
  default = 14
}

variable "max_connections" {
  type    = number
  default = 100
}

variable "performance_insights_enabled" {
  description = "Not available on db.t4g.micro/small"
  type        = bool
  default     = true
}

variable "monitoring_interval" {
  description = "Enhanced monitoring interval in seconds (0 disables)"
  type        = number
  default     = 60
}
