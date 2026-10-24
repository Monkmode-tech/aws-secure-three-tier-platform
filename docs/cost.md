# Cost

> Figures are **approximate us-east-2 on-demand list prices** used for planning.
> Prices change; confirm with the [AWS Pricing Calculator](https://calculator.aws/)
> before relying on them.

## While the environment is running

| Component | Sizing | Approx. per hour |
|-----------|--------|------------------|
| NAT gateway | 1 (single_nat_gateway = true) | $0.045 + data processed |
| Application Load Balancer | 1 + light LCU usage | $0.023 |
| Public IPv4 addresses | 3 ALB nodes + 1 NAT EIP | $0.020 |
| ECS Fargate (Graviton) | 2 tasks x 0.5 vCPU / 1 GB | $0.040 |
| RDS MariaDB db.t4g.micro | Multi-AZ, 20 GB gp3 | $0.035 |
| AWS WAF | 1 web ACL, 6 rules (monthly fees prorated) | $0.015 |
| **Total** | | **about $0.18 / hour** |

Left running 24/7 that is roughly **$130 / month**, more than the $50 budget.
That is why the workflow is **deploy, capture evidence, destroy**:

| Session | Approx. cost |
|---------|--------------|
| Deploy + validate + load test + destroy (about 4 hours) | under $1 |
| Four sessions a month | about $3-4 |

## Small fixed monthly costs

KMS key ($1/month while it exists), Secrets Manager (2 secrets), Route 53 hosted
zone, CloudWatch dashboard beyond the free tier, and the domain registration
itself (yearly). The bootstrap S3 state bucket costs cents.

## Cost levers built into the variables

| Variable | Default | Effect |
|----------|---------|--------|
| `single_nat_gateway` | `true` | One NAT instead of three |
| `cpu_architecture` (app module) | `ARM64` | Graviton Fargate pricing is lower than x86 |
| `db_instance_class` | `db.t4g.micro` | Smallest Graviton class |
| `db_multi_az` | `true` | Set `false` to halve the database cost when HA isn't being demonstrated |
| `enable_interface_endpoints` | `false` | Interface endpoints bill per AZ-hour |
| `enable_scheduled_scaling` | `false` | Scale to 1 task overnight for longer-lived environments |
| `log_retention_days` | `30` | Bounded log storage |

## Guardrail

`bootstrap/` creates an account-wide **$50 monthly AWS Budget** that emails at
50% and 80% of actual spend and when the month is forecast to exceed 100%.
