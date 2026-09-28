variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "image" {
  description = "settle-api image by digest (set by the pipeline: the digest that passed verification)"
  type        = string
}

variable "app_version" {
  type = string
}

variable "certificate_arn" {
  type = string
}

variable "bank_url" {
  type = string
}
