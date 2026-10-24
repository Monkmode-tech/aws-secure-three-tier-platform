###############################################################################
# Edge module
#
# Internet-facing entry point:
#   Route 53 alias -> ALB (HTTPS, TLS 1.2/1.3 policy, HTTP->HTTPS redirect)
#   AWS WAF web ACL in front of the ALB (managed rule groups + per-IP rate limit)
#   ALB access logs -> S3; WAF logs -> KMS-encrypted CloudWatch Logs
#
# HTTPS is enabled when `domain_name` is set to a public hosted zone in this
# account. Without a domain the ALB serves plain HTTP so the stack can still be
# demonstrated; the README calls this out as a degraded mode.
###############################################################################

locals {
  enable_https = var.domain_name != ""
  fqdn         = local.enable_https ? (var.app_subdomain == "" ? var.domain_name : "${var.app_subdomain}.${var.domain_name}") : ""

  # AWS managed rule groups (no extra subscription cost). Rules listed in
  # `count_rules` are set to COUNT instead of BLOCK; see docs/adr/0004.
  managed_rule_groups = [
    { name = "AWSManagedRulesAmazonIpReputationList", priority = 10, count_rules = [] },
    { name = "AWSManagedRulesCommonRuleSet", priority = 20, count_rules = ["SizeRestrictions_BODY"] },
    { name = "AWSManagedRulesKnownBadInputsRuleSet", priority = 30, count_rules = [] },
    { name = "AWSManagedRulesSQLiRuleSet", priority = 40, count_rules = [] },
    { name = "AWSManagedRulesWordPressRuleSet", priority = 50, count_rules = [] },
  ]

  cert_validation_options = local.enable_https ? tolist(aws_acm_certificate.this[0].domain_validation_options) : []
}

data "aws_caller_identity" "current" {}

data "aws_elb_service_account" "this" {}

#------------------------------------------------------------------------------
# ALB access-log bucket (ALB log delivery supports SSE-S3 only)
#------------------------------------------------------------------------------
resource "aws_s3_bucket" "alb_logs" {
  count = var.enable_access_logs ? 1 : 0

  bucket_prefix = "${var.name}-alb-logs-"
  force_destroy = var.force_destroy_log_bucket
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  count = var.enable_access_logs ? 1 : 0

  bucket                  = aws_s3_bucket.alb_logs[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "alb_logs" {
  count = var.enable_access_logs ? 1 : 0

  bucket = aws_s3_bucket.alb_logs[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  count = var.enable_access_logs ? 1 : 0

  bucket = aws_s3_bucket.alb_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "alb_logs" {
  count = var.enable_access_logs ? 1 : 0

  bucket = aws_s3_bucket.alb_logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  count = var.enable_access_logs ? 1 : 0

  bucket = aws_s3_bucket.alb_logs[0].id

  rule {
    id     = "expire-access-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.access_log_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

data "aws_iam_policy_document" "alb_logs" {
  count = var.enable_access_logs ? 1 : 0

  statement {
    sid       = "AllowELBLogDelivery"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.alb_logs[0].arn}/alb/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.this.arn]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.alb_logs[0].arn, "${aws_s3_bucket.alb_logs[0].arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  count = var.enable_access_logs ? 1 : 0

  bucket = aws_s3_bucket.alb_logs[0].id
  policy = data.aws_iam_policy_document.alb_logs[0].json

  depends_on = [aws_s3_bucket_public_access_block.alb_logs]
}

#------------------------------------------------------------------------------
# Application Load Balancer
#------------------------------------------------------------------------------
resource "aws_lb" "this" {
  # checkov:skip=CKV2_AWS_76: Log4j coverage comes from AWSManagedRulesKnownBadInputsRuleSet (priority 30), defined in a dynamic block checkov does not expand
  name                       = "${var.name}-alb"
  load_balancer_type         = "application"
  internal                   = false
  security_groups            = [var.alb_security_group_id]
  subnets                    = var.public_subnet_ids
  drop_invalid_header_fields = true
  enable_deletion_protection = var.deletion_protection

  dynamic "access_logs" {
    for_each = var.enable_access_logs ? [1] : []

    content {
      bucket  = aws_s3_bucket.alb_logs[0].id
      prefix  = "alb"
      enabled = true
    }
  }

  tags = { Name = "${var.name}-alb" }

  depends_on = [aws_s3_bucket_policy.alb_logs]
}

resource "aws_lb_target_group" "app" {
  name                 = "${var.name}-app"
  port                 = var.app_port
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path                = var.health_check_path
    matcher             = "200-399"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "${var.name}-app-tg" }
}

#------------------------------------------------------------------------------
# TLS certificate + DNS (only when a domain is configured)
#------------------------------------------------------------------------------
data "aws_route53_zone" "this" {
  count = local.enable_https ? 1 : 0

  name         = var.domain_name
  private_zone = false
}

resource "aws_acm_certificate" "this" {
  count = local.enable_https ? 1 : 0

  domain_name       = local.fqdn
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${var.name}-cert" }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in local.cert_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = data.aws_route53_zone.this[0].zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  count = local.enable_https ? 1 : 0

  certificate_arn         = aws_acm_certificate.this[0].arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

resource "aws_route53_record" "app" {
  count = local.enable_https ? 1 : 0

  zone_id = data.aws_route53_zone.this[0].zone_id
  name    = local.fqdn
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}

#------------------------------------------------------------------------------
# Listeners
#------------------------------------------------------------------------------
resource "aws_lb_listener" "http" {
  # checkov:skip=CKV_AWS_2: HTTP listener only redirects to HTTPS when a domain is set; plain HTTP is the documented no-domain demo mode
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = local.enable_https ? "redirect" : "forward"
    target_group_arn = local.enable_https ? null : aws_lb_target_group.app.arn

    dynamic "redirect" {
      for_each = local.enable_https ? [1] : []

      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }
}

resource "aws_lb_listener" "https" {
  count = local.enable_https ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = aws_acm_certificate_validation.this[0].certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

#------------------------------------------------------------------------------
# AWS WAF
#------------------------------------------------------------------------------
resource "aws_wafv2_web_acl" "this" {
  name        = "${var.name}-web-acl"
  description = "Managed rule groups and per-IP rate limiting for ${var.name}"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "rate-limit-per-ip"
    priority = 0

    action {
      dynamic "block" {
        for_each = var.waf_rate_limit_action == "block" ? [1] : []

        content {}
      }

      dynamic "count" {
        for_each = var.waf_rate_limit_action == "count" ? [1] : []
        iterator = rate_count

        content {}
      }
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  dynamic "rule" {
    for_each = local.managed_rule_groups

    content {
      name     = rule.value.name
      priority = rule.value.priority

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = rule.value.name
          vendor_name = "AWS"

          dynamic "rule_action_override" {
            for_each = rule.value.count_rules

            content {
              name = rule_action_override.value

              action_to_use {
                count {}
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name}-${rule.value.name}"
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-web-acl"
    sampled_requests_enabled   = true
  }

  tags = { Name = "${var.name}-web-acl" }
}

resource "aws_wafv2_web_acl_association" "this" {
  resource_arn = aws_lb.this.arn
  web_acl_arn  = aws_wafv2_web_acl.this.arn
}

# WAF requires the destination log group name to start with "aws-waf-logs-".
resource "aws_cloudwatch_log_group" "waf" {
  name              = "aws-waf-logs-${var.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  resource_arn            = aws_wafv2_web_acl.this.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]

  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  redacted_fields {
    single_header {
      name = "cookie"
    }
  }
}
