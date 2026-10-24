###############################################################################
# Network module
#
# Three-tier VPC spread across `az_count` Availability Zones:
#   public  - ALB and NAT gateway(s) only; the only tier with an internet route
#   app     - ECS Fargate tasks; egress to the internet through NAT only
#   data    - RDS; no route to the internet at all, guarded by a dedicated NACL
#
# CIDR plan (for the default 10.0.0.0/16):
#   public  10.0.0.0/24  - 10.0.2.0/24
#   app     10.0.10.0/24 - 10.0.12.0/24
#   data    10.0.20.0/24 - 10.0.22.0/24
###############################################################################

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  # checkov:skip=CKV_AWS_394: AZ list is sliced to az_count; new AZs sort after existing ones, so the selection is stable
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  public_subnets = { for i, az in local.azs : az => cidrsubnet(var.vpc_cidr, 8, i) }
  app_subnets    = { for i, az in local.azs : az => cidrsubnet(var.vpc_cidr, 8, i + 10) }
  data_subnets   = { for i, az in local.azs : az => cidrsubnet(var.vpc_cidr, 8, i + 20) }

  # One NAT gateway (cost-optimised, see docs/adr/0002) or one per AZ (HA).
  nat_azs = var.single_nat_gateway ? [local.azs[0]] : local.azs

  interface_endpoints = var.enable_interface_endpoints ? toset(["ecr.api", "ecr.dkr", "logs", "secretsmanager"]) : toset([])
}

#------------------------------------------------------------------------------
# VPC
#------------------------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name}-vpc" }
}

# CIS AWS Foundations 5.4: the default security group must allow no traffic.
# Declaring it with no rules makes Terraform strip the AWS-created rules.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-default-deny-all" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-igw" }
}

#------------------------------------------------------------------------------
# Subnets
#------------------------------------------------------------------------------
resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = false

  tags = { Name = "${var.name}-public-${each.key}", Tier = "public" }
}

resource "aws_subnet" "app" {
  for_each = local.app_subnets

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = { Name = "${var.name}-app-${each.key}", Tier = "app" }
}

resource "aws_subnet" "data" {
  for_each = local.data_subnets

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = { Name = "${var.name}-data-${each.key}", Tier = "data" }
}

#------------------------------------------------------------------------------
# NAT gateway(s)
#------------------------------------------------------------------------------
resource "aws_eip" "nat" {
  for_each = toset(local.nat_azs)

  domain = "vpc"

  tags = { Name = "${var.name}-nat-eip-${each.key}" }
}

resource "aws_nat_gateway" "this" {
  for_each = toset(local.nat_azs)

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id

  tags = { Name = "${var.name}-nat-${each.key}" }

  depends_on = [aws_internet_gateway.this]
}

#------------------------------------------------------------------------------
# Route tables
#------------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-public-rt" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# One app route table per AZ so per-AZ NAT is a one-variable change.
resource "aws_route_table" "app" {
  for_each = toset(local.azs)

  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-app-rt-${each.key}" }
}

resource "aws_route" "app_nat" {
  for_each = aws_route_table.app

  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[var.single_nat_gateway ? local.azs[0] : each.key].id
}

resource "aws_route_table_association" "app" {
  for_each = aws_subnet.app

  subnet_id      = each.value.id
  route_table_id = aws_route_table.app[each.key].id
}

# Data tier: local VPC route only. No IGW, no NAT.
resource "aws_route_table" "data" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-data-rt" }
}

resource "aws_route_table_association" "data" {
  for_each = aws_subnet.data

  subnet_id      = each.value.id
  route_table_id = aws_route_table.data.id
}

#------------------------------------------------------------------------------
# Data-tier network ACL (stateless second layer behind the DB security group)
#------------------------------------------------------------------------------
resource "aws_network_acl" "data" {
  vpc_id     = aws_vpc.this.id
  subnet_ids = [for s in aws_subnet.data : s.id]

  tags = { Name = "${var.name}-data-nacl" }
}

locals {
  data_nacl_ingress = merge(
    { for i, cidr in values(local.app_subnets) : "db-from-app-${i}" => {
      rule_number = 100 + i
      protocol    = "tcp"
      cidr_block  = cidr
      from_port   = var.db_port
      to_port     = var.db_port
    } },
    { for i, cidr in values(local.data_subnets) : "intra-data-${i}" => {
      rule_number = 200 + i
      protocol    = "-1"
      cidr_block  = cidr
      from_port   = 0
      to_port     = 0
    } },
  )

  data_nacl_egress = merge(
    { for i, cidr in values(local.app_subnets) : "ephemeral-to-app-${i}" => {
      rule_number = 100 + i
      protocol    = "tcp"
      cidr_block  = cidr
      from_port   = 1024
      to_port     = 65535
    } },
    { for i, cidr in values(local.data_subnets) : "intra-data-${i}" => {
      rule_number = 200 + i
      protocol    = "-1"
      cidr_block  = cidr
      from_port   = 0
      to_port     = 0
    } },
  )
}

resource "aws_network_acl_rule" "data_ingress" {
  for_each = local.data_nacl_ingress

  network_acl_id = aws_network_acl.data.id
  egress         = false
  rule_number    = each.value.rule_number
  rule_action    = "allow"
  protocol       = each.value.protocol
  cidr_block     = each.value.cidr_block
  from_port      = each.value.from_port
  to_port        = each.value.to_port
}

resource "aws_network_acl_rule" "data_egress" {
  for_each = local.data_nacl_egress

  network_acl_id = aws_network_acl.data.id
  egress         = true
  rule_number    = each.value.rule_number
  rule_action    = "allow"
  protocol       = each.value.protocol
  cidr_block     = each.value.cidr_block
  from_port      = each.value.from_port
  to_port        = each.value.to_port
}

#------------------------------------------------------------------------------
# VPC endpoints
#------------------------------------------------------------------------------
# Gateway endpoint for S3 is free and keeps S3 traffic off the NAT gateway.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [for rt in aws_route_table.app : rt.id]

  tags = { Name = "${var.name}-s3-endpoint" }
}

# Interface endpoints are billed per AZ-hour, so they are opt-in.
resource "aws_security_group" "endpoints" {
  count = var.enable_interface_endpoints ? 1 : 0

  name        = "${var.name}-vpc-endpoints"
  description = "HTTPS from inside the VPC to interface endpoints"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${var.name}-vpc-endpoints" }
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_https" {
  count = var.enable_interface_endpoints ? 1 : 0

  security_group_id = aws_security_group.endpoints[0].id
  description       = "HTTPS from the VPC"
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoints

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [for s in aws_subnet.app : s.id]
  security_group_ids  = [aws_security_group.endpoints[0].id]

  tags = { Name = "${var.name}-${each.key}-endpoint" }
}

#------------------------------------------------------------------------------
# VPC flow logs -> KMS-encrypted CloudWatch Logs
#------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/vpc/${var.name}/flow-logs"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

data "aws_iam_policy_document" "flow_logs_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "flow_logs" {
  statement {
    sid       = "WriteFlowLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = ["${aws_cloudwatch_log_group.flow_logs.arn}:*"]
  }

  statement {
    sid       = "DescribeLogGroups"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:*"]
  }
}

resource "aws_iam_role" "flow_logs" {
  name               = "${var.name}-vpc-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json
}

resource "aws_iam_role_policy" "flow_logs" {
  name   = "write-flow-logs"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs.json
}

resource "aws_flow_log" "this" {
  vpc_id                   = aws_vpc.this.id
  traffic_type             = "ALL"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow_logs.arn
  iam_role_arn             = aws_iam_role.flow_logs.arn
  max_aggregation_interval = 60

  tags = { Name = "${var.name}-flow-logs" }
}
