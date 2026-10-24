#!/usr/bin/env bash
# shellcheck disable=SC2016  # backticks inside single quotes are JMESPath literals, not shell
#
# watch-scaling.sh - record ECS scaling behaviour while a load test runs.
#
# Every INTERVAL seconds it prints (and appends to a CSV in docs/evidence/)
# the desired/running task counts, average service CPU over the last minute,
# and the number of healthy ALB targets.
#
# Usage:  INTERVAL=30 ./scripts/watch-scaling.sh      (Ctrl-C to stop)
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_DIR="${ENV_DIR:-$ROOT_DIR/environments/dev}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/docs/evidence}"
INTERVAL="${INTERVAL:-30}"
CSV="$OUT_DIR/scaling-$(date -u +%Y%m%dT%H%M%SZ).csv"

REGION="$(terraform -chdir="$ENV_DIR" output -raw aws_region)"
CLUSTER="$(terraform -chdir="$ENV_DIR" output -raw ecs_cluster_name)"
SERVICE="$(terraform -chdir="$ENV_DIR" output -raw ecs_service_name)"
export AWS_REGION="$REGION" AWS_PAGER=""

TG_ARN="$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
  --query 'services[0].loadBalancers[0].targetGroupArn' --output text)"

mkdir -p "$OUT_DIR"
echo "timestamp_utc,desired,running,pending,cpu_avg_1m,healthy_targets" | tee "$CSV"

while true; do
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  read -r desired running pending < <(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
    --query 'services[0].[desiredCount,runningCount,pendingCount]' --output text)

  cpu="$(aws cloudwatch get-metric-statistics --namespace AWS/ECS --metric-name CPUUtilization \
    --dimensions "Name=ClusterName,Value=$CLUSTER" "Name=ServiceName,Value=$SERVICE" \
    --start-time "$(date -u -d '-2 minutes' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-2M +%Y-%m-%dT%H:%M:%SZ)" \
    --end-time "$now" --period 60 --statistics Average \
    --query 'sort_by(Datapoints,&Timestamp)[-1].Average' --output text)"
  if [[ "$cpu" == "None" ]]; then cpu=""; else cpu="$(printf '%.1f' "$cpu")"; fi

  healthy="$(aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
    --query 'length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])' --output text)"

  echo "$now,$desired,$running,$pending,$cpu,$healthy" | tee -a "$CSV"
  sleep "$INTERVAL"
done
