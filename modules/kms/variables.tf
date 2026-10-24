variable "name" {
  description = "Name prefix; the key alias becomes alias/<name>."
  type        = string
}

variable "aws_region" {
  description = "Region of the CloudWatch Logs service principal allowed to use the key."
  type        = string
}

variable "deletion_window_in_days" {
  description = "Waiting period before a scheduled key deletion completes (7-30)."
  type        = number
  default     = 7
}
