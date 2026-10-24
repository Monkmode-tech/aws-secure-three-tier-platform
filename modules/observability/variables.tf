variable "name" {
  description = "Name prefix for alarms, topic and dashboard."
  type        = string
}

variable "aws_region" {
  description = "Region shown on dashboard widgets."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key for the SNS topic."
  type        = string
}

variable "alert_email" {
  description = "Email subscribed to alarm notifications (confirm the subscription email AWS sends). Empty = no subscription."
  type        = string
  default     = ""
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix."
  type        = string
}

variable "target_group_arn_suffix" {
  description = "Target group ARN suffix."
  type        = string
}

variable "cluster_name" {
  description = "ECS cluster name."
  type        = string
}

variable "service_name" {
  description = "ECS service name."
  type        = string
}

variable "db_identifier" {
  description = "RDS instance identifier."
  type        = string
}

variable "web_acl_name" {
  description = "WAF web ACL name."
  type        = string
}

variable "cpu_target_percent" {
  description = "CPU scaling target, drawn on the dashboard."
  type        = number
}

variable "latency_p90_threshold_seconds" {
  description = "Alarm threshold for p90 target response time."
  type        = number
  default     = 1.5
}
