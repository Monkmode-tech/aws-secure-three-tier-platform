# Hardening: v1 (course lab) to v2 (this repository)

This project started as the Terraform WordPress lab from **CLCS 645 Cloud
Infrastructure Planning and Design (UMGC)**, extended in the course capstone with
ECS autoscaling and load-testing scripts. The lab worked, and its disaster
recovery exercise recovered the application in about 42 seconds. But it was
built to get running quickly, not to be secure.

I reviewed the original code the way a security reviewer would, then rebuilt it.
Every finding below maps to a specific change in this repo.

| # | v1 finding | Risk | v2 change | Where |
|---|------------|------|-----------|-------|
| 1 | ECS tasks ran in **public subnets with public IPs** (`assign_public_ip = true`) | Containers directly addressable from the internet | Tasks run in private app subnets with no public IPs; egress via NAT only | `modules/network`, `modules/app` |
| 2 | Tasks **shared the ALB security group**, which allowed port 80 from `0.0.0.0/0` | Anyone could hit a task directly, bypassing the load balancer | Separate ALB / app / DB groups; the app group only admits the ALB group | `modules/security-groups` |
| 3 | The **RDS subnet group used the public subnets** | One misconfiguration away from an internet-reachable database | Dedicated data subnets with no default route, plus a NACL that only admits the app subnets | `modules/network`, `modules/database` |
| 4 | **DB password passed as a plain environment variable** in the task definition, and a weak default password was hard-coded in `variables.tf` | Anyone with `ecs:DescribeTaskDefinition` could read it; it was also in state and in git | RDS generates the password and stores it in Secrets Manager (`manage_master_user_password`); ECS injects it at start via `secrets` / `valueFrom` | `modules/database`, `modules/app` |
| 5 | **AWS access keys were Terraform variables**, filled in from a local `terraform.tfvars` | Keys leak the moment that file is committed or shared | No key variables at all. Credentials come from the AWS CLI profile / SSO locally and from GitHub OIDC in CI. `*.tfvars` is git-ignored and pre-commit runs gitleaks | `bootstrap/`, `.gitignore`, `.pre-commit-config.yaml` |
| 6 | **HTTP only**, no TLS | Credentials and session cookies in clear text | ACM certificate, HTTPS listener with a TLS 1.3/1.2-only policy, HTTP 301 redirect | `modules/edge` |
| 7 | **No WAF** | No protection from common web exploits or floods | AWS WAF with five AWS managed rule groups plus a per-IP rate limit, with logging | `modules/edge` |
| 8 | **Single-AZ RDS**, storage encryption not enabled | AZ outage = full outage; unencrypted data at rest | Multi-AZ, gp3, storage + secret encrypted with a customer-managed KMS key, 7-day PITR backups | `modules/database`, `modules/kms` |
| 9 | `desired_count = 1`, autoscaling bolted on later from a separate stack | One task = no redundancy | Minimum 2 tasks across AZs; CPU and request-count target tracking built into the module | `modules/app` |
| 10 | `wordpress:latest` image | Unreviewed changes on every deploy | Explicit tag, enforced by a variable validation that rejects `:latest` | `modules/app` |
| 11 | Logs unencrypted, 7-day retention, no flow logs, no alarms | Little ability to investigate or notice an incident | KMS-encrypted logs, VPC flow logs, WAF logs, ALB access logs, 8 alarms to SNS, dashboard | `modules/*`, `modules/observability` |
| 12 | Deprecated `template_file` data source, everything in one folder | Hard to reuse or review | Seven focused modules, `jsonencode` task definition, CI with fmt / validate / tflint / checkov | whole repo |
| 13 | Each task generated its own WordPress auth salts | Users logged out whenever the ALB switched tasks | Shared salts generated once and stored in Secrets Manager | `modules/app` |
| 14 | VPC default security group left open | CIS AWS Foundations 5.4 finding | Default security group managed with no rules | `modules/network` |

## How each fix is verified

`scripts/validate-security.sh` checks findings 1-4, 6-8, 11 and 14 against the
live account and writes a PASS/FAIL report to `docs/evidence/`. Findings 5, 10 and
12 are enforced at review time by CI (checkov, variable validation,
`.gitignore` + gitleaks).
