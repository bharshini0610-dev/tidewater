output "alb_dns_name" {
  value = module.alb.dns_name
}

output "ecr_repository_url" {
  value = aws_ecr_repository.api.repository_url
}

output "db_connection_budget" {
  description = "Peak DB connections at max scale during a deploy (must be <= max_connections)"
  value       = local.db_budget
}
