output "cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.this.name
}

output "service_name" {
  description = "ECS service name."
  value       = aws_ecs_service.app.name
}

output "task_definition_family" {
  description = "Task definition family."
  value       = aws_ecs_task_definition.app.family
}

output "log_group_name" {
  description = "Container log group."
  value       = aws_cloudwatch_log_group.app.name
}

output "wp_salts_secret_arn" {
  description = "Secrets Manager ARN of the shared WordPress salts."
  value       = aws_secretsmanager_secret.wp_salts.arn
}
