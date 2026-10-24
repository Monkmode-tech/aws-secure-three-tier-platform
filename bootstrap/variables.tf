variable "aws_region" {
  description = "Region for the state bucket (match the environments)."
  type        = string
  default     = "us-east-2"
}

variable "github_repository" {
  description = "owner/repo allowed to assume the plan role."
  type        = string
  default     = "Monkmode-tech/aws-secure-three-tier-platform"
}

variable "plan_role_name" {
  description = "Name of the IAM role GitHub Actions assumes for terraform plan."
  type        = string
  default     = "gha-plan-aws-secure-three-tier-platform"
}

variable "state_key_prefix" {
  description = "State key prefix this repo uses inside the bucket."
  type        = string
  default     = "aws-secure-three-tier-platform"
}

variable "project_secret_prefix" {
  description = "Secrets Manager name prefix of secrets the plan role may read (<project>-<env>)."
  type        = string
  default     = "wp3t-dev"
}

variable "create_github_oidc_provider" {
  description = "Create the account's GitHub OIDC provider. Set false if it already exists."
  type        = bool
  default     = true
}

variable "create_budget" {
  description = "Create the account-wide monthly budget. Set false if another repo already did."
  type        = bool
  default     = true
}

variable "monthly_budget_usd" {
  description = "Monthly cost budget in USD."
  type        = number
  default     = 50
}

variable "budget_alert_email" {
  description = "Email that receives budget alerts."
  type        = string
}
