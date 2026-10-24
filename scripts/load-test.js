// k6 ramp test - the same 10 -> 200 virtual-user ramp used in the CLCS 645
// capstone (gradual_ramp_test.sh), rewritten for k6 so results are reproducible
// and thresholds fail the run automatically.
//
// Before running from a single machine, set waf_rate_limit_action = "count"
// and apply, otherwise the WAF rate rule will (correctly) block your IP.
//
//   TARGET_URL=https://app.example.com k6 run scripts/load-test.js
//   TARGET_URL=... k6 run --summary-export docs/evidence/k6-summary.json scripts/load-test.js

import http from 'k6/http';
import { check, sleep } from 'k6';

const TARGET_URL = __ENV.TARGET_URL;
if (!TARGET_URL) {
  throw new Error('Set TARGET_URL, e.g. TARGET_URL=$(terraform -chdir=environments/dev output -raw app_url)');
}

export const options = {
  stages: [
    { duration: '1m', target: 10 },
    { duration: '2m', target: 25 },
    { duration: '2m', target: 50 },
    { duration: '3m', target: 100 },
    { duration: '3m', target: 150 },
    { duration: '4m', target: 200 }, // hold at peak long enough for scale-out
    { duration: '3m', target: 0 },   // ramp down; watch scale-in after cooldown
  ],
  thresholds: {
    http_req_failed: ['rate<0.02'],    // < 2% errors
    http_req_duration: ['p(95)<2000'], // p95 under 2 s while scaling
  },
};

export default function () {
  const res = http.get(`${TARGET_URL}/`, { tags: { page: 'home' } });
  check(res, {
    'status is 200': (r) => r.status === 200,
  });
  sleep(1);
}
