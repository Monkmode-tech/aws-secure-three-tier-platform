variable "name" {
  description = "Name prefix for the security groups."
  type        = string
}

variable "vpc_id" {
  description = "VPC the security groups belong to."
  type        = string
}

variable "app_port" {
  description = "Port the application container listens on."
  type        = number
  default     = 80
}

variable "db_port" {
  description = "Database port."
  type        = number
  default     = 3306
}
