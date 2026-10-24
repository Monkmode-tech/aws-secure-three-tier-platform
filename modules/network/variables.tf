variable "name" {
  description = "Name prefix applied to every resource (e.g. wp3t-dev)."
  type        = string
}

variable "aws_region" {
  description = "AWS region, used to build VPC endpoint service names."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block. Must be a /16 so the /24 subnet plan fits."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && endswith(var.vpc_cidr, "/16")
    error_message = "vpc_cidr must be a valid /16 CIDR block."
  }
}

variable "az_count" {
  description = "Number of Availability Zones to span (2 or 3)."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "single_nat_gateway" {
  description = "true = one NAT gateway for all AZs (cheaper); false = one NAT gateway per AZ (no cross-AZ dependency)."
  type        = bool
  default     = true
}

variable "enable_interface_endpoints" {
  description = "Create interface endpoints for ECR, CloudWatch Logs and Secrets Manager (billed per AZ-hour)."
  type        = bool
  default     = false
}

variable "db_port" {
  description = "Database port allowed through the data-tier NACL."
  type        = number
  default     = 3306
}

variable "kms_key_arn" {
  description = "KMS key used to encrypt the flow-log log group."
  type        = string
}

variable "log_retention_days" {
  description = "Retention for VPC flow logs."
  type        = number
  default     = 30
}
