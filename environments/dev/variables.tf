#------------------------------------------------------------------------------
# General
#------------------------------------------------------------------------------
variable "aws_region" {
  description = "Region to deploy into."
  type        = string
  default     = "us-east-2"
}

variable "project" {
  description = "Short project code used in resource names."
  type        = string
  default     = "wp3t"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Owner tag value."
  type        = string
  default     = "caleb-tetteh"
}

variable "log_retention_days" {
  description = "Retention for all CloudWatch log groups."
  type        = number
  default     = 30
}

variable "deletion_protection" {
  description = "Deletion protection on the ALB and RDS. Leave false for short-lived lab deployments."
  type        = bool
  default     = false
}

#------------------------------------------------------------------------------
# Network
#------------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "VPC CIDR (/16)."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Availability Zones to span."
  type        = number
  default     = 3
}

variable "single_nat_gateway" {
  description = "One shared NAT gateway (cheaper) vs one per AZ (higher availability)."
  type        = bool
  default     = true
}

variable "enable_interface_endpoints" {
  description = "Interface endpoints for ECR, Logs and Secrets Manager."
  type        = bool
  default     = false
}

#------------------------------------------------------------------------------
# Edge
#------------------------------------------------------------------------------
variable "domain_name" {
  description = "Public Route 53 hosted zone you own (e.g. example.com). Empty = HTTP-only demo mode."
  type        = string
  default     = ""
}

variable "app_subdomain" {
  description = "App hostname under domain_name."
  type        = string
  default     = "app"
}

variable "waf_rate_limit" {
  description = "Requests per IP per 5 minutes before the WAF rate rule triggers."
  type        = number
  default     = 2000
}

variable "waf_rate_limit_action" {
  description = "block normally; count while running a load test from a single IP."
  type        = string
  default     = "block"
}

#------------------------------------------------------------------------------
# App
#------------------------------------------------------------------------------
variable "container_image" {
  description = "WordPress image with an explicit tag."
  type        = string
  default     = "wordpress:6-apache"
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

variable "min_capacity" {
  description = "Minimum tasks."
  type        = number
  default     = 2
}

variable "max_capacity" {
  description = "Maximum tasks."
  type        = number
  default     = 6
}

variable "cpu_target_percent" {
  description = "CPU target-tracking value."
  type        = number
  default     = 60
}

variable "requests_per_target" {
  description = "ALB requests per task per minute target."
  type        = number
  default     = 300
}

variable "enable_scheduled_scaling" {
  description = "Night-time scale-in schedule."
  type        = bool
  default     = false
}

variable "enable_execute_command" {
  description = "Allow ECS Exec for troubleshooting."
  type        = bool
  default     = false
}

#------------------------------------------------------------------------------
# Database
#------------------------------------------------------------------------------
variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_multi_az" {
  description = "Multi-AZ standby."
  type        = bool
  default     = true
}

variable "db_skip_final_snapshot" {
  description = "Skip the final snapshot on destroy."
  type        = bool
  default     = true
}

#------------------------------------------------------------------------------
# Observability
#------------------------------------------------------------------------------
variable "alert_email" {
  description = "Email for alarm notifications."
  type        = string
  default     = ""
}
