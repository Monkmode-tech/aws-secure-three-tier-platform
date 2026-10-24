variable "name" {
  description = "Name prefix. Keep it short: ALB and target group names are limited to 32 characters."
  type        = string

  validation {
    condition     = length(var.name) <= 24
    error_message = "name must be 24 characters or fewer so derived ALB/target group names fit in 32."
  }
}

variable "vpc_id" {
  description = "VPC for the target group."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets for the ALB (at least two AZs)."
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group attached to the ALB."
  type        = string
}

variable "app_port" {
  description = "Port the targets listen on."
  type        = number
  default     = 80
}

variable "health_check_path" {
  description = "Target group health-check path."
  type        = string
  default     = "/"
}

variable "domain_name" {
  description = "Public Route 53 hosted zone in this account (e.g. example.com). Empty = HTTP-only demo mode."
  type        = string
  default     = ""
}

variable "app_subdomain" {
  description = "Subdomain for the app (app -> app.example.com). Empty string uses the zone apex."
  type        = string
  default     = "app"
}

variable "ssl_policy" {
  description = "ALB TLS policy. The default allows TLS 1.3 and 1.2 only."
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "deletion_protection" {
  description = "Enable ALB deletion protection (turn on for anything long-lived)."
  type        = bool
  default     = false
}

variable "enable_access_logs" {
  description = "Ship ALB access logs to S3."
  type        = bool
  default     = true
}

variable "access_log_retention_days" {
  description = "Days to keep ALB access logs in S3."
  type        = number
  default     = 90
}

variable "force_destroy_log_bucket" {
  description = "Allow terraform destroy to delete a non-empty log bucket (convenient for labs)."
  type        = bool
  default     = true
}

variable "waf_rate_limit" {
  description = "Max requests per source IP in any 5-minute window before the rate rule triggers."
  type        = number
  default     = 2000

  validation {
    condition     = var.waf_rate_limit >= 10 && var.waf_rate_limit <= 2000000000
    error_message = "waf_rate_limit must be between 10 and 2,000,000,000."
  }
}

variable "waf_rate_limit_action" {
  description = "block in normal operation; count during load tests so the test IP is observed, not blocked."
  type        = string
  default     = "block"

  validation {
    condition     = contains(["block", "count"], var.waf_rate_limit_action)
    error_message = "waf_rate_limit_action must be \"block\" or \"count\"."
  }
}

variable "kms_key_arn" {
  description = "KMS key for the WAF log group."
  type        = string
}

variable "log_retention_days" {
  description = "Retention for WAF logs in CloudWatch."
  type        = number
  default     = 30
}
