output "alb_arn" {
  description = "ALB ARN."
  value       = aws_lb.this.arn
}

output "alb_arn_suffix" {
  description = "ALB ARN suffix (CloudWatch LoadBalancer dimension)."
  value       = aws_lb.this.arn_suffix
}

output "alb_dns_name" {
  description = "ALB DNS name."
  value       = aws_lb.this.dns_name
}

output "target_group_arn" {
  description = "Target group ARN for the ECS service."
  value       = aws_lb_target_group.app.arn
}

output "target_group_arn_suffix" {
  description = "Target group ARN suffix (CloudWatch TargetGroup dimension)."
  value       = aws_lb_target_group.app.arn_suffix
}

output "alb_resource_label" {
  description = "Resource label for the ALBRequestCountPerTarget scaling metric."
  value       = "${aws_lb.this.arn_suffix}/${aws_lb_target_group.app.arn_suffix}"
}

output "https_enabled" {
  description = "Whether the HTTPS listener and DNS record were created."
  value       = local.enable_https
}

output "app_url" {
  description = "URL to open in a browser."
  value       = local.enable_https ? "https://${local.fqdn}" : "http://${aws_lb.this.dns_name}"
}

output "web_acl_name" {
  description = "WAF web ACL name (CloudWatch WebACL dimension)."
  value       = aws_wafv2_web_acl.this.name
}

output "web_acl_arn" {
  description = "WAF web ACL ARN."
  value       = aws_wafv2_web_acl.this.arn
}

output "access_log_bucket" {
  description = "S3 bucket receiving ALB access logs (null when disabled)."
  value       = var.enable_access_logs ? aws_s3_bucket.alb_logs[0].id : null
}
