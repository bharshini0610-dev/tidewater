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
  type = list(string)
}

variable "kms_key_arn" {
  type = string
}

variable "node_type" {
  type    = string
  default = "cache.m7g.large"
}

variable "replicas" {
  description = "Read replicas (>= 1 enables automatic failover across the 2 AZs)"
  type        = number
  default     = 1
}

variable "multi_az" {
  description = "Automatic failover to the replica in the other AZ (requires replicas >= 1)"
  type        = bool
  default     = true
}

variable "snapshot_retention_days" {
  type    = number
  default = 7
}
