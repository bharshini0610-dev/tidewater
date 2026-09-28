variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "certificate_arn" {
  description = "ACM certificate for the public hostname"
  type        = string
}

variable "target_port" {
  type    = number
  default = 8000
}

variable "allowed_ingress_cidr" {
  description = "Who may reach the API (0.0.0.0/0 for public merchants, a partner range for staging)"
  type        = string
  default     = "0.0.0.0/0"
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "kms_key_arn" {
  description = "CMK for the WAF log group"
  type        = string
}

variable "waf_rate_limit" {
  description = "Requests per 5 minutes per client IP before WAF blocks"
  type        = number
  default     = 3000
}

variable "log_retention_days" {
  type    = number
  default = 90
}
