# ADR 0004: WAF rule selection and tuning

**Status:** Accepted

## Decision

| Priority | Rule | Action | Why |
|----------|------|--------|-----|
| 0 | Rate limit per IP (`waf_rate_limit`, default 2000 / 5 min) | Block (or Count) | Slows credential stuffing against `wp-login.php` and scraping |
| 10 | AWSManagedRulesAmazonIpReputationList | Block | Known malicious sources |
| 20 | AWSManagedRulesCommonRuleSet | Block, except `SizeRestrictions_BODY` = Count | OWASP Top 10 coverage; body-size rule would block media uploads in wp-admin |
| 30 | AWSManagedRulesKnownBadInputsRuleSet | Block | Log4j-style and other known exploit payloads |
| 40 | AWSManagedRulesSQLiRuleSet | Block | WordPress plugins are a common SQL injection target |
| 50 | AWSManagedRulesWordPressRuleSet | Block | WordPress-specific exploit patterns |

All six together stay under the default 1,500 WCU web ACL capacity.

## Load testing

A load test from one machine looks exactly like the abuse the rate rule exists to
stop. Instead of disabling the rule, `waf_rate_limit_action = "count"` keeps it
evaluating and emitting `CountedRequests`, so the test proves the rule **would**
have fired, then it goes back to `block`.

## Logging

Full WAF logs go to a KMS-encrypted CloudWatch log group with the
`authorization` and `cookie` headers redacted, so logs never contain session tokens.
