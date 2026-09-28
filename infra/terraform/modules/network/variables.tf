variable "name" {
  description = "Prefix for resource names, e.g. settle-staging"
  type        = string
}

variable "cidr_block" {
  type    = string
  default = "10.40.0.0/16"
}

variable "single_nat_gateway" {
  description = "One NAT for both AZs (staging cost saving) instead of one per AZ (prod HA)"
  type        = bool
  default     = false
}

variable "enable_interface_endpoints" {
  description = "ECR/Secrets Manager/Logs interface endpoints (~USD 7/month each per AZ)"
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  type = string
}

variable "log_retention_days" {
  type    = number
  default = 365
}

variable "availability_zones" {
  description = "Exactly two AZs, pinned so the layout never changes when AWS adds zones"
  type        = list(string)
  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "settle is designed for exactly 2 AZs."
  }
}
