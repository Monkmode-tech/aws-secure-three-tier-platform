#!/usr/bin/env bash
#
# smoke-test.sh - quick post-deploy check that the site answers through the ALB.
#
# Usage:  ./scripts/smoke-test.sh
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_DIR="${ENV_DIR:-$ROOT_DIR/environments/dev}"
APP_URL="$(terraform -chdir="$ENV_DIR" output -raw app_url)"

echo "Checking $APP_URL ..."
for attempt in $(seq 1 20); do
  code="$(curl -s -o /dev/null -L -w '%{http_code}' --max-time 10 "$APP_URL/" || true)"
  if [[ "$code" == "200" ]]; then
    echo "OK: $APP_URL returned 200 (attempt $attempt)"
    exit 0
  fi
  echo "  attempt $attempt: HTTP $code - waiting for tasks to become healthy"
  sleep 15
done

echo "FAILED: $APP_URL did not return 200. Check: terraform output ecs_log_group" >&2
exit 1
