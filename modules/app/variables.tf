variable "name" {
  description = "Name prefix for ECS, IAM and Secrets Manager resources."
  type        = string
}

variable "aws_region" {
  description = "Region for the awslogs driver."
  type        = string
}

variable "app_subnet_ids" {
  description = "Private app subnets for the tasks."
  type        = list(string)
}

variable "app_security_group_id" {
  description = "Security group for the tasks."
  type        = string
}

variable "target_group_arn" {
  description = "ALB target group the service registers with."
  type        = string
}

variable "alb_resource_label" {
  description = "<alb arn suffix>/<target group arn suffix> for request-count scaling."
  type        = string
}

variable "https_enabled" {
  description = "Whether the ALB terminates HTTPS (sets FORCE_SSL_ADMIN)."
  type        = bool
}

variable "kms_key_arn" {
  description = "KMS key for logs, secrets and ECS Exec."
  type        = string
}

variable "container_image" {
  description = "WordPress image. Pin a version tag (or digest for production); never :latest."
  type        = string
  default     = "wordpress:6-apache"

  validation {
    condition     = !endswith(var.container_image, ":latest") && strcontains(var.container_image, ":")
    error_message = "container_image must include an explicit, non-latest tag."
  }
}

variable "cpu_architecture" {
  description = "ARM64 (Graviton, cheaper) or X86_64. The official WordPress image publishes both."
  type        = string
  default     = "ARM64"

  validation {
    condition     = contains(["ARM64", "X86_64"], var.cpu_architecture)
    error_message = "cpu_architecture must be ARM64 or X86_64."
  }
}

variable "app_port" {
  description = "Container port."
  type        = number
  default     = 80
}

variable "task_cpu" {
  description = "Fargate task CPU units."
  type        = number
  default     = 512
}

variable "task_memory" {
  description = "Fargate task memory (MiB)."
  type        = number
  default     = 1024
}

variable "db_host" {
  description = "Database hostname."
  type        = string
}

variable "db_port" {
  description = "Database port."
  type        = number
}

variable "db_name" {
  description = "Database name."
  type        = string
}

variable "db_secret_arn" {
  description = "Secrets Manager ARN of the RDS-managed credentials (JSON with username and password)."
  type        = string
}

variable "min_capacity" {
  description = "Minimum (and initial) number of tasks. 2+ keeps the app up if an AZ fails."
  type        = number
  default     = 2
}

variable "max_capacity" {
  description = "Maximum number of tasks."
  type        = number
  default     = 6
}

variable "cpu_target_percent" {
  description = "Target average CPU utilisation for target tracking."
  type        = number
  default     = 60
}

variable "requests_per_target" {
  description = "Target ALB requests per task per minute."
  type        = number
  default     = 300
}

variable "enable_scheduled_scaling" {
  description = "Scale in at night and back out in the morning."
  type        = bool
  default     = false
}

variable "schedule_timezone" {
  description = "IANA time zone for scheduled scaling."
  type        = string
  default     = "America/New_York"
}

variable "enable_execute_command" {
  description = "Allow ECS Exec shell sessions (audited, KMS-encrypted) for troubleshooting."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Retention for container logs."
  type        = number
  default     = 30
}

variable "secret_recovery_window_days" {
  description = "Days a deleted salts secret can be recovered (0 deletes immediately)."
  type        = number
  default     = 7
}
