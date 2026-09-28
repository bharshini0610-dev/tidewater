output "address" {
  value = aws_db_instance.this.address
}

output "port" {
  value = aws_db_instance.this.port
}

output "master_user_secret_arn" {
  description = "Secrets Manager secret (JSON: username, password) managed and rotated by RDS"
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "security_group_id" {
  value = aws_security_group.this.id
}
