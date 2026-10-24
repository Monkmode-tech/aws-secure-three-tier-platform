output "state_bucket" {
  description = "Put this in environments/dev/backend.hcl."
  value       = aws_s3_bucket.state.id
}

output "plan_role_arn" {
  description = "Set as the AWS_PLAN_ROLE_ARN repository variable in GitHub."
  value       = aws_iam_role.plan.arn
}

output "github_oidc_provider_arn" {
  description = "GitHub OIDC provider ARN (reuse it from other repos)."
  value       = local.github_oidc_provider_arn
}
