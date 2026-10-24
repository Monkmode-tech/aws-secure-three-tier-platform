# Security controls

| Domain | Control | Implementation | Verified by |
|--------|---------|----------------|-------------|
| Network | Three-tier segmentation | Public / app / data subnets; only public has an IGW route | `validate-security.sh` (route checks) |
| Network | Least-privilege security groups | SG-to-SG references only; DB has no egress | `validate-security.sh` |
| Network | Defense in depth for data | Stateless NACL on data subnets admits only app subnet CIDRs on 3306 | Terraform plan / console |
| Network | Default SG closed | `aws_default_security_group` with no rules (CIS 5.4) | `validate-security.sh` |
| Network | Traffic visibility | VPC flow logs (ALL, 60 s aggregation) to KMS-encrypted log group | `validate-security.sh` |
| Edge | Encryption in transit | ACM cert, `ELBSecurityPolicy-TLS13-1-2-2021-06`, HTTP 301 to HTTPS | `validate-security.sh` |
| Edge | Web application firewall | IP reputation, Core rule set, known bad inputs, SQLi, WordPress rules, rate limit | `validate-security.sh`; WAF metrics on dashboard |
| Edge | Request hygiene | ALB `drop_invalid_header_fields` | `validate-security.sh` |
| Identity | No long-lived keys | Local SSO/CLI profile; GitHub OIDC role scoped to this repo for CI | `bootstrap/main.tf` trust policy |
| Identity | Least-privilege task roles | Execution role reads only its two secrets and the env key; task role is empty unless ECS Exec is on | IAM policy documents in `modules/app` |
| Secrets | No secrets in code, state or task definitions | RDS-managed master secret; salts secret; `valueFrom` injection | `validate-security.sh` |
| Data | Encryption at rest | One customer-managed KMS key (rotation on) for RDS, secrets, logs, SNS | `validate-security.sh` (RDS) |
| Data | Backups | 7-day automated backups + PITR, final snapshot optional | `validate-security.sh` |
| Availability | Multi-AZ | 3 AZ tasks, RDS Multi-AZ, circuit-breaker rollback | load test + failover drill (runbook) |
| Detection | Alerting | 8 CloudWatch alarms to a KMS-encrypted SNS topic | Alarm widget on the dashboard |
| Detection | Audit of shell access | ECS Exec sessions encrypted and logged to CloudWatch | `docs/runbook.md` |
| Supply chain | Pinned images | Variable validation rejects untagged or `:latest` images | `terraform validate` |
| Supply chain | IaC scanning | fmt, validate, tflint, checkov, shellcheck on every PR | GitHub Actions |
| Cost | Spend guardrail | $50/month AWS Budget with 50% / 80% / 100%-forecast alerts | `bootstrap/` |

## Accepted risks (lab scope)

These are deliberate trade-offs, each listed as a skipped check in `.checkov.yaml`.

| Item | Why it is acceptable here | Production change |
|------|---------------------------|-------------------|
| Deletion protection off (ALB, RDS) | The environment is created and destroyed per demo | `deletion_protection = true` |
| 30-day log retention | Keeps CloudWatch cost inside the budget | 1 year+, archive to S3 Glacier |
| No TLS between WordPress and RDS | Traffic stays in private subnets; WordPress needs extra client config for TLS | `require_secure_transport` + `MYSQL_CLIENT_FLAGS` |
| Single NAT gateway | Saves roughly a NAT gateway's hourly charge per extra AZ | `single_nat_gateway = false` |
| ECS root filesystem writable | WordPress writes plugins/uploads locally | Move uploads to EFS or S3 and make the container read-only |
| Uploads not shared between tasks | Out of scope for this infrastructure demo | EFS volume or S3 offload plugin |
| CloudTrail / GuardDuty / Security Hub not in this repo | Account-level detection is the job of `aws-security-guardrails-detection` | Deploy that repo in the same account |
