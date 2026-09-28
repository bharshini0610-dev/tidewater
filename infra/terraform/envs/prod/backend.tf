# Remote state in S3 with native S3 locking (Terraform >= 1.10, ADR-005).
# The bucket name is account-specific and passed at init:
#   terraform init -backend-config="bucket=paylane-settle-tfstate-<account-id>"
terraform {
  backend "s3" {
    key          = "settle/prod/terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }
}
