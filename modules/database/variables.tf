variable "name" {
  description = "Name prefix; the instance identifier becomes <name>-db."
  type        = string
}

variable "data_subnet_ids" {
  description = "Isolated data-tier subnets (no internet route)."
  type        = list(string)
}

variable "db_security_group_id" {
  description = "Security group that only admits the app tier."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key for storage, the master secret and log groups."
  type        = string
}

variable "engine_version" {
  description = "MariaDB major.minor version; RDS picks the latest patch."
  type        = string
  default     = "10.11"
}

variable "parameter_group_family" {
  description = "Parameter group family matching engine_version."
  type        = string
  default     = "mariadb10.11"
}

variable "instance_class" {
  description = "Instance class. Graviton (t4g) costs less than the equivalent t3 size."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "wordpress"
}

variable "master_username" {
  description = "Master username. The password is generated and stored by RDS in Secrets Manager."
  type        = string
  default     = "wpadmin"
}

variable "db_port" {
  description = "Database port."
  type        = number
  default     = 3306
}

variable "allocated_storage" {
  description = "Initial storage in GiB."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Storage autoscaling ceiling in GiB."
  type        = number
  default     = 50
}

variable "multi_az" {
  description = "Run a synchronous standby in a second AZ."
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Automated backup retention (enables point-in-time restore)."
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "Block accidental deletion (turn on for anything long-lived)."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on destroy (true is convenient for short-lived labs)."
  type        = bool
  default     = false
}

variable "apply_immediately" {
  description = "Apply modifications now instead of in the maintenance window."
  type        = bool
  default     = true
}

variable "cloudwatch_logs_exports" {
  description = "MariaDB log types exported to CloudWatch Logs."
  type        = list(string)
  default     = ["error", "slowquery"]
}

variable "monitoring_interval" {
  description = "Enhanced Monitoring interval in seconds (0 disables; 1, 5, 10, 15, 30 or 60)."
  type        = number
  default     = 60

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be one of 0, 1, 5, 10, 15, 30, 60."
  }
}

variable "log_retention_days" {
  description = "Retention for exported database logs."
  type        = number
  default     = 30
}
