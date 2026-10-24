# ADR 0001: ECS on Fargate for the app tier

**Status:** Accepted

## Context

The application is a single stateless-enough container (WordPress + Apache).
Options considered: EC2 Auto Scaling group, ECS on EC2, ECS on Fargate, EKS.

## Decision

ECS on Fargate, Graviton (ARM64).

## Rationale

- **No servers to patch or SSH into.** There is no AMI, no OS hardening backlog
  and no bastion host - the security story is simpler and the attack surface smaller.
- **Per-task isolation and per-task security groups** (`awsvpc` networking).
- **Autoscaling on service metrics** (CPU, ALB requests per target) with no
  capacity-provider tuning.
- The original lab already used ECS Fargate, so the v1 to v2 comparison is like-for-like.
- EKS adds a control-plane fee and cluster operations that a single service
  doesn't need. Kubernetes is demonstrated separately in `eks-devsecops-pipeline`.

## Consequences

- Fargate costs more per vCPU-hour than well-packed EC2, acceptable at this scale.
- No host-level access; troubleshooting uses logs and ECS Exec (audited).
