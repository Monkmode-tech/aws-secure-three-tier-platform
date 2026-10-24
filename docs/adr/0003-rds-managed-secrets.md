# ADR 0003: Let RDS own the database password

**Status:** Accepted

## Context

The v1 lab took the database password as a Terraform variable (with a weak
hard-coded default) and rendered it into the task definition as a plain
environment variable. That puts the secret in git history, in Terraform state
and in every `DescribeTaskDefinition` response.

Options considered:

1. `random_password` + `aws_secretsmanager_secret` managed by Terraform
2. `manage_master_user_password = true` (RDS generates and stores the secret)
3. IAM database authentication

## Decision

Option 2. ECS reads the secret at task start through the task definition's
`secrets` / `valueFrom` (`<secret-arn>:password::`). The secret is encrypted with
the environment's customer-managed KMS key.

## Rationale

- The password never exists in Terraform variables, state, plans or code.
- RDS rotates the managed secret automatically.
- IAM auth (option 3) would be stronger, but WordPress cannot request IAM auth tokens.

## Consequences

- Rotation changes the password; running tasks keep their old connection
  credentials until they restart. Force a new deployment after a rotation
  (`aws ecs update-service --force-new-deployment`).
- WordPress salts are a different case: they must be identical on every task,
  so Terraform generates them once (option 1) and accepts that they live in the
  encrypted state file.
