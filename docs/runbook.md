# Runbook

Everything here runs from a workstation with the AWS CLI v2, Terraform >= 1.10,
`jq`, `curl` and (for load tests) [k6](https://grafana.com/docs/k6/latest/set-up/install-k6/).

## 0. Credentials

Use an IAM Identity Center (SSO) profile or an IAM user with MFA - never paste
access keys into Terraform files.

```bash
aws configure sso            # one time
export AWS_PROFILE=portfolio
aws sts get-caller-identity  # confirm the account
```

## 1. Bootstrap (once per account)

```bash
cd bootstrap
terraform init
terraform apply -var="budget_alert_email=you@example.com"
terraform output            # note state_bucket and plan_role_arn
```

Budget alert emails need no confirmation. The bootstrap uses local state on
purpose (it creates the remote-state bucket); keep `bootstrap/terraform.tfstate`
somewhere safe, or re-import the resources if it is lost.

If another repo already created the GitHub OIDC provider or the budget in this
account, add `-var="create_github_oidc_provider=false"` and/or
`-var="create_budget=false"`.

## 2. Domain and hosted zone

Register a cheap domain in Route 53 (**Route 53 > Registered domains**). A
public hosted zone is created automatically. If you buy the domain elsewhere,
create a public hosted zone in Route 53 and point the registrar's name servers
at the four NS records it lists.

## 3. Deploy

```bash
cd environments/dev
cp backend.hcl.example backend.hcl            # set bucket = <state_bucket>
cp terraform.tfvars.example terraform.tfvars  # set domain_name, alert_email
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan
terraform apply tfplan                        # ~20-25 min, RDS Multi-AZ is the slow part
```

Then:

1. Confirm the SNS subscription email from AWS.
2. `../../scripts/smoke-test.sh`
3. Open `terraform output -raw app_url` and finish the WordPress installer
   (site title, admin user with a strong password).
4. Commit `.terraform.lock.hcl` the first time it is created.

## 4. Validate security

```bash
./scripts/validate-security.sh
```

Expect all PASS. The report lands in `docs/evidence/security-validation-<timestamp>.txt`.

## 5. Load test and observe autoscaling

```bash
# a) Let the WAF count (not block) your single test IP
#    set waf_rate_limit_action = "count" in terraform.tfvars, then:
terraform -chdir=environments/dev apply

# b) Terminal 1 - record scaling
./scripts/watch-scaling.sh

# c) Terminal 2 - generate load (about 18 minutes)
TARGET_URL=$(terraform -chdir=environments/dev output -raw app_url) \
  k6 run --summary-export docs/evidence/k6-summary.json scripts/load-test.js

# d) Restore blocking
#    set waf_rate_limit_action = "block" and apply again
```

While it runs, open `terraform output -raw dashboard_url`. Expected behaviour:
CPU crosses the 60% line, desired tasks step up from 2 toward 6, healthy
targets follow 1-2 minutes later, and the WAF "Counted" series shows the
rate rule would have fired. After the test, tasks scale back in once the 5-minute
scale-in cooldowns have passed.

## 6. Failure drills

**Task failure (self-healing)**

```bash
CLUSTER=$(terraform -chdir=environments/dev output -raw ecs_cluster_name)
TASK=$(aws ecs list-tasks --cluster "$CLUSTER" --query 'taskArns[0]' --output text)
aws ecs stop-task --cluster "$CLUSTER" --task "$TASK" --reason "failure drill"
```

Watch the service replace it; the site stays up because the other task keeps serving.

**Database AZ failover**

```bash
DB=$(terraform -chdir=environments/dev output -raw db_identifier)
date -u; aws rds reboot-db-instance --db-instance-identifier "$DB" --force-failover
aws rds describe-events --source-identifier "$DB" --source-type db-instance --duration 30
```

Time how long the site returns errors (run `smoke-test.sh` in a loop). Record
the start/end events from `describe-events` as evidence.

## 7. Troubleshooting

| Symptom | Check |
|---------|-------|
| 503 from the ALB | `aws ecs describe-services ... --query 'services[0].events[:5]'` - tasks failing to start? |
| Tasks stop immediately | Container logs: `aws logs tail $(terraform output -raw ecs_log_group) --since 15m` |
| `ResourceInitializationError ... secrets` | Execution role can't read a secret or the KMS key - compare ARNs in `modules/app` |
| Certificate stuck "Pending validation" | `domain_name` must be a public hosted zone in this account with correct NS at the registrar |
| 403 from WAF during tests | Rate rule fired - set `waf_rate_limit_action = "count"` while load testing |
| Need a shell in a task | Set `enable_execute_command = true`, apply, then `aws ecs execute-command --cluster ... --task ... --container wordpress --interactive --command /bin/bash` (requires the Session Manager plugin). Sessions are logged to `/ecs/<name>/exec-sessions` |

## 8. Destroy (do this after every session)

```bash
terraform -chdir=environments/dev destroy
```

The KMS key enters a 7-day pending-deletion window; secrets enter their
recovery window. Leave `bootstrap/` in place - it costs cents per month.
