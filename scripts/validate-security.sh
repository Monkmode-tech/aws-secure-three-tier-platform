#!/usr/bin/env bash
# shellcheck disable=SC2016  # backticks inside single quotes are JMESPath literals, not shell
#
# validate-security.sh - prove the deployed stack matches the security design.
#
# Reads Terraform outputs from environments/dev, queries the live AWS account
# with the AWS CLI and prints a PASS/FAIL line per control. A copy of the
# report is written to docs/evidence/ so it can be committed as evidence.
#
# Usage:  ./scripts/validate-security.sh
# Needs:  aws (v2), jq, curl, terraform; credentials for the target account.
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_DIR="${ENV_DIR:-$ROOT_DIR/environments/dev}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/docs/evidence}"
REPORT="$OUT_DIR/security-validation-$(date -u +%Y%m%dT%H%M%SZ).txt"

for bin in aws jq curl terraform; do
  command -v "$bin" >/dev/null || { echo "missing dependency: $bin" >&2; exit 2; }
done

tf_raw()  { terraform -chdir="$ENV_DIR" output -raw "$1"; }
tf_json() { terraform -chdir="$ENV_DIR" output -json "$1"; }

REGION="$(tf_raw aws_region)"
CLUSTER="$(tf_raw ecs_cluster_name)"
SERVICE="$(tf_raw ecs_service_name)"
DB_ID="$(tf_raw db_identifier)"
ALB_ARN="$(tf_raw alb_arn)"
ALB_DNS="$(tf_raw alb_dns_name)"
APP_URL="$(tf_raw app_url)"
VPC_ID="$(tf_raw vpc_id)"
APP_SG="$(tf_raw app_security_group_id)"
HTTPS_ENABLED="$(tf_json https_enabled)"

export AWS_REGION="$REGION" AWS_PAGER=""

mkdir -p "$OUT_DIR"
exec > >(tee "$REPORT") 2>&1

PASS=0
FAIL=0
SKIP=0

check() {
  local description="$1"; shift
  if "$@"; then
    printf 'PASS  %s\n' "$description"; PASS=$((PASS + 1))
  else
    printf 'FAIL  %s\n' "$description"; FAIL=$((FAIL + 1))
  fi
}

skip() {
  printf 'SKIP  %s\n' "$1"; SKIP=$((SKIP + 1))
}

# Returns success if the subnet's route table has a 0.0.0.0/0 route whose
# target id starts with the given prefix ("igw-", "nat-", or "" for any).
subnet_default_route_via() {
  local subnet="$1" prefix="$2" targets
  targets="$(aws ec2 describe-route-tables \
    --filters "Name=association.subnet-id,Values=$subnet" \
    --query 'RouteTables[].Routes[?DestinationCidrBlock==`0.0.0.0/0`][].[GatewayId,NatGatewayId]' \
    --output text)"
  [[ -n "${targets//[[:space:]]/}" ]] || return 1 # no default route at all
  [[ -z "$prefix" ]] && return 0                  # any default route counts
  grep -Eq "(^|[[:space:]])${prefix}" <<<"$targets"
}

#------------------------------------------------------------------------------
echo "Security validation for ${CLUSTER%-cluster} in $REGION"
echo "Run at $(date -u '+%Y-%m-%d %H:%M:%SZ') by $(aws sts get-caller-identity --query Arn --output text)"
echo "------------------------------------------------------------------------"

#--- App tier -----------------------------------------------------------------
svc_public_ip_setting() {
  [[ "$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
    --query 'services[0].networkConfiguration.awsvpcConfiguration.assignPublicIp' \
    --output text)" == "DISABLED" ]]
}
check "ECS service does not assign public IPs to tasks" svc_public_ip_setting

TASK_ARNS="$(aws ecs list-tasks --cluster "$CLUSTER" --service-name "$SERVICE" \
  --desired-status RUNNING --query 'taskArns' --output text)"

if [[ -z "$TASK_ARNS" || "$TASK_ARNS" == "None" ]]; then
  skip "Running task ENIs have no public IP (no running tasks)"
  skip "Running tasks sit in subnets with no internet gateway route (no running tasks)"
else
  # shellcheck disable=SC2086 # word-splitting the ARN list is intended
  TASKS_JSON="$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks $TASK_ARNS)"
  ENIS="$(jq -r '.tasks[].attachments[].details[] | select(.name=="networkInterfaceId") | .value' <<<"$TASKS_JSON")"
  TASK_SUBNETS="$(jq -r '.tasks[].attachments[].details[] | select(.name=="subnetId") | .value' <<<"$TASKS_JSON" | sort -u)"

  task_enis_private() {
    local public_ips
    # shellcheck disable=SC2086
    public_ips="$(aws ec2 describe-network-interfaces --network-interface-ids $ENIS \
      --query 'NetworkInterfaces[].Association.PublicIp' --output text)"
    [[ -z "$public_ips" || "$public_ips" == "None" ]]
  }
  check "Running task ENIs have no public IP" task_enis_private

  task_subnets_private() {
    local s
    for s in $TASK_SUBNETS; do
      subnet_default_route_via "$s" "igw-" && return 1
      subnet_default_route_via "$s" "nat-" || return 1
    done
    return 0
  }
  check "Running tasks sit in subnets that egress via NAT, never an internet gateway" task_subnets_private
fi

no_plaintext_db_password() {
  local td
  td="$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
    --query 'services[0].taskDefinition' --output text)"
  aws ecs describe-task-definition --task-definition "$td" --query 'taskDefinition.containerDefinitions[0]' |
    jq -e '([.environment[]?.name] | index("WORDPRESS_DB_PASSWORD") | not)
           and ([.secrets[]?.name] | index("WORDPRESS_DB_PASSWORD") != null)' >/dev/null
}
check "Task definition injects the DB password from Secrets Manager, not plain env" no_plaintext_db_password

#--- Data tier ----------------------------------------------------------------
DB_JSON="$(aws rds describe-db-instances --db-instance-identifier "$DB_ID" --query 'DBInstances[0]')"

db_is() { jq -e "$1" <<<"$DB_JSON" >/dev/null; }

check "RDS is not publicly accessible" db_is '.PubliclyAccessible == false'
check "RDS is Multi-AZ" db_is '.MultiAZ == true'
check "RDS storage is encrypted with a KMS key" db_is '.StorageEncrypted == true and ((.KmsKeyId // "") | length > 0)'
check "RDS master password is managed in Secrets Manager" db_is '((.MasterUserSecret.SecretArn // "") | length > 0)'
check "RDS automated backups are retained >= 7 days" db_is '.BackupRetentionPeriod >= 7'

db_subnets_isolated() {
  local s
  for s in $(jq -r '.DBSubnetGroup.Subnets[].SubnetIdentifier' <<<"$DB_JSON"); do
    subnet_default_route_via "$s" "" && return 1
  done
  return 0
}
check "RDS subnets have no default route (no IGW, no NAT)" db_subnets_isolated

db_sg_only_from_app() {
  local sg
  sg="$(jq -r '.VpcSecurityGroups[0].VpcSecurityGroupId' <<<"$DB_JSON")"
  aws ec2 describe-security-groups --group-ids "$sg" --query 'SecurityGroups[0]' |
    jq -e --arg app "$APP_SG" '
      (.IpPermissions | length > 0)
      and all(.IpPermissions[]; (.IpRanges | length == 0) and (.Ipv6Ranges | length == 0)
                                and all(.UserIdGroupPairs[]; .GroupId == $app))
      and (.IpPermissionsEgress | length == 0)' >/dev/null
}
check "DB security group admits only the app security group and has no egress" db_sg_only_from_app

#--- Edge ---------------------------------------------------------------------
waf_attached() {
  [[ "$(aws wafv2 get-web-acl-for-resource --resource-arn "$ALB_ARN" \
    --query 'WebACL.Name' --output text)" != "None" ]]
}
check "AWS WAF web ACL is associated with the ALB" waf_attached

alb_drops_invalid_headers() {
  [[ "$(aws elbv2 describe-load-balancer-attributes --load-balancer-arn "$ALB_ARN" \
    --query 'Attributes[?Key==`routing.http.drop_invalid_header_fields.enabled`].Value' \
    --output text)" == "true" ]]
}
check "ALB drops invalid HTTP header fields" alb_drops_invalid_headers

if [[ "$HTTPS_ENABLED" == "true" ]]; then
  HOST="${APP_URL#https://}"

  http_redirects() {
    local result
    result="$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' "http://$HOST/")"
    [[ "$result" == 301\ https://* ]]
  }
  check "HTTP requests are redirected (301) to HTTPS" http_redirects

  tls_policy() {
    aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN" \
      --query 'Listeners[?Protocol==`HTTPS`].SslPolicy' --output text | grep -q '^ELBSecurityPolicy-TLS13'
  }
  check "HTTPS listener uses a TLS 1.3/1.2-only policy" tls_policy
else
  skip "HTTP->HTTPS redirect (no domain configured; HTTP demo mode at http://$ALB_DNS)"
  skip "TLS policy (no domain configured)"
fi

#--- Network hygiene ----------------------------------------------------------
flow_logs_on() {
  [[ "$(aws ec2 describe-flow-logs --filter "Name=resource-id,Values=$VPC_ID" \
    --query 'length(FlowLogs[?FlowLogStatus==`ACTIVE`])' --output text)" -ge 1 ]]
}
check "VPC flow logs are active" flow_logs_on

default_sg_closed() {
  aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=default" \
    --query 'SecurityGroups[0]' |
    jq -e '(.IpPermissions | length == 0) and (.IpPermissionsEgress | length == 0)' >/dev/null
}
check "VPC default security group allows no traffic (CIS 5.4)" default_sg_closed

echo "------------------------------------------------------------------------"
echo "Result: $PASS passed, $FAIL failed, $SKIP skipped"
echo "Report saved to ${REPORT#"$ROOT_DIR"/}"

[[ "$FAIL" -eq 0 ]]
