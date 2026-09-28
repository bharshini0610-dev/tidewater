output "security_group_id" {
  value = aws_security_group.alb.id
}

output "target_group_arn" {
  value = aws_lb_target_group.api.arn
}

output "dns_name" {
  value = aws_lb.this.dns_name
}

output "deployment_alarm_name" {
  value = aws_cloudwatch_metric_alarm.target_5xx.alarm_name
}
