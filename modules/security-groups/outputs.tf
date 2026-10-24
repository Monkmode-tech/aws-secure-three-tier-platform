output "alb_security_group_id" {
  description = "Security group for the public ALB."
  value       = aws_security_group.alb.id
}

output "app_security_group_id" {
  description = "Security group for the ECS tasks."
  value       = aws_security_group.app.id
}

output "db_security_group_id" {
  description = "Security group for the RDS instance."
  value       = aws_security_group.db.id
}
