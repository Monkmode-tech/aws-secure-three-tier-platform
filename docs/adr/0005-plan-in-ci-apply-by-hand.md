# ADR 0005: CI plans, humans apply

**Status:** Accepted

## Context

Running `terraform apply` from CI needs a role that can create IAM roles, KMS
keys and networks - effectively admin. For a personal account with a $50 budget,
a compromised workflow with that role is the worst-case incident.

## Decision

- Every pull request runs static checks (fmt, validate, tflint, checkov,
  shellcheck) with **no AWS access at all**.
- If `AWS_PLAN_ROLE_ARN` is set, PRs also run `terraform plan` through GitHub
  OIDC using a **read-only** role whose trust policy only accepts this
  repository's pull requests and `main` branch. The plan is posted to the PR.
- `terraform apply` runs from a workstation using SSO credentials, after the
  plan has been reviewed.

## Consequences

- No long-lived AWS keys exist anywhere, and CI can never change infrastructure.
- Applies are not fully automated. The next step would be a protected GitHub
  Environment with required reviewers and a separate, narrowly scoped apply role.
