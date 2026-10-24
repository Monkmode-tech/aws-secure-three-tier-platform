###############################################################################
# Security groups
#
# All tier-to-tier rules live in one module so the segmentation can be reviewed
# in a single file and so cross-references between groups never create module
# dependency cycles.
#
#   internet --80/443--> alb --app_port--> app --db_port--> db
#                                          app --443------> internet (via NAT)
#
# The db group has no egress rules at all.
###############################################################################

resource "aws_security_group" "alb" {
  # checkov:skip=CKV2_AWS_5: Attached to the ALB in modules/edge; checkov cannot follow the module output
  name        = "${var.name}-alb"
  description = "Public ALB: HTTP/HTTPS in from the internet, app port out to the app tier only"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-alb", Tier = "public" }
}

resource "aws_security_group" "app" {
  # checkov:skip=CKV2_AWS_5: Attached to the ECS service in modules/app; checkov cannot follow the module output
  name        = "${var.name}-app"
  description = "ECS tasks: app port from the ALB only; HTTPS out and DB port to the data tier"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-app", Tier = "app" }
}

resource "aws_security_group" "db" {
  # checkov:skip=CKV2_AWS_5: Attached to the RDS instance in modules/database; checkov cannot follow the module output
  name        = "${var.name}-db"
  description = "RDS: DB port from the app tier only; no egress"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-db", Tier = "data" }
}

#------------------------------------------------------------------------------
# ALB
#------------------------------------------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  # checkov:skip=CKV_AWS_260: Public port 80 exists only to 301-redirect to HTTPS (ALB listener)
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from the internet (redirected to HTTPS when a domain is configured)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from the internet"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward to app tasks"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
}

#------------------------------------------------------------------------------
# App
#------------------------------------------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  # checkov:skip=CKV_AWS_260: False positive - source is the ALB security group, not 0.0.0.0/0
  security_group_id            = aws_security_group.app.id
  description                  = "App port from the ALB only"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
}

resource "aws_vpc_security_group_egress_rule" "app_https_out" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS out via NAT: image pulls, AWS APIs, WordPress updates"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "app_to_db" {
  security_group_id            = aws_security_group.app.id
  description                  = "Database connections to the data tier"
  referenced_security_group_id = aws_security_group.db.id
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
}

#------------------------------------------------------------------------------
# DB
#------------------------------------------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "Database port from the app tier only"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
}
