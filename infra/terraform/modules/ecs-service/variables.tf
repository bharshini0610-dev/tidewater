variable "name" {
  type = string
}

variable "cluster_arn" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "image" {
  description = "Image reference pinned by digest (repo@sha256:...)"
  type        = string
  validation {
    condition     = can(regex("@sha256:[a-f0-9]{64}$", var.image))
    error_message = "Deploy images by digest, never by mutable tag."
  }
}

variable "command" {
  type    = list(string)
  default = null
}

variable "cpu" {
  type = number
}

variable "memory" {
  type = number
}

variable "min_count" {
  type = number
}

variable "max_count" {
  type = number
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "container_port" {
  description = "null for services without HTTP ingress (worker)"
  type        = number
  default     = null
}

variable "target_group_arn" {
  type    = string
  default = null
}

variable "alb_security_group_id" {
  type    = string
  default = null
}

variable "environment" {
  type    = map(string)
  default = {}
}

variable "secrets" {
  description = "ENV_NAME => Secrets Manager valueFrom (ARN or ARN:json-key::)"
  type        = map(string)
  default     = {}
}

variable "secret_arns" {
  description = "Secret ARNs the execution role may read"
  type        = list(string)
}

variable "kms_key_arn" {
  type = string
}

variable "health_check_command" {
  type    = list(string)
  default = null
}

variable "stop_timeout" {
  description = "Seconds between SIGTERM and SIGKILL (Fargate max 120)"
  type        = number
  default     = 45
}

variable "deployment_alarm_names" {
  type    = list(string)
  default = []
}

variable "log_retention_days" {
  type    = number
  default = 365
}

variable "deployment_maximum_percent" {
  description = "Surge during deploys; counts against the DB connection budget"
  type        = number
  default     = 200
}
