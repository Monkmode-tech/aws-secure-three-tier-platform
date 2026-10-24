output "aws_region" {
  description = "Deployment region (used by scripts/)."
  value       = var.aws_region
}

output "app_url" {
  description = "Open this in a browser to finish the WordPress install."
  value       = module.edge.app_url
}

output "alb_dns_name" {
  description = "ALB DNS name."
  value       = module.edge.alb_dns_name
}

output "alb_arn" {
  description = "ALB ARN."
  value       = module.edge.alb_arn
}

output "https_enabled" {
  description = "Whether HTTPS and DNS were configured."
  value       = module.edge.https_enabled
}

output "web_acl_arn" {
  description = "WAF web ACL ARN."
  value       = module.edge.web_acl_arn
}

output "vpc_id" {
  description = "VPC ID."
  value       = module.network.vpc_id
}

output "app_subnet_ids" {
  description = "Private app subnets."
  value       = module.network.app_subnet_ids
}

output "data_subnet_ids" {
  description = "Isolated data subnets."
  value       = module.network.data_subnet_ids
}

output "nat_public_ips" {
  description = "Egress IPs of the app tier."
  value       = module.network.nat_public_ips
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = module.app.cluster_name
}

output "ecs_service_name" {
  description = "ECS service name."
  value       = module.app.service_name
}

output "ecs_log_group" {
  description = "Container log group."
  value       = module.app.log_group_name
}

output "db_identifier" {
  description = "RDS instance identifier."
  value       = module.database.identifier
}

output "db_secret_arn" {
  description = "RDS-managed credentials secret (the password is never in Terraform state)."
  value       = module.database.master_user_secret_arn
}

output "app_security_group_id" {
  description = "App tier security group."
  value       = module.security_groups.app_security_group_id
}

output "db_security_group_id" {
  description = "DB tier security group."
  value       = module.security_groups.db_security_group_id
}

output "dashboard_url" {
  description = "CloudWatch dashboard."
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards/dashboard/${module.observability.dashboard_name}"
}

output "alerts_topic_arn" {
  description = "SNS alert topic."
  value       = module.observability.alerts_topic_arn
}
