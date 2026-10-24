###############################################################################
# dev environment
#
#   Route 53 -> WAF -> ALB (public subnets)
#                       -> ECS Fargate WordPress (private app subnets, NAT egress)
#                            -> RDS MariaDB Multi-AZ (isolated data subnets)
#
# See docs/architecture.md for the diagram and docs/hardening-v1-to-v2.md for
# how this differs from the original CLCS 645 lab.
###############################################################################

locals {
  name     = "${var.project}-${var.environment}"
  app_port = 80
  db_port  = 3306
}

module "kms" {
  source = "../../modules/kms"

  name       = local.name
  aws_region = var.aws_region
}

module "network" {
  source = "../../modules/network"

  name                       = local.name
  aws_region                 = var.aws_region
  vpc_cidr                   = var.vpc_cidr
  az_count                   = var.az_count
  single_nat_gateway         = var.single_nat_gateway
  enable_interface_endpoints = var.enable_interface_endpoints
  db_port                    = local.db_port
  kms_key_arn                = module.kms.key_arn
  log_retention_days         = var.log_retention_days
}

module "security_groups" {
  source = "../../modules/security-groups"

  name     = local.name
  vpc_id   = module.network.vpc_id
  app_port = local.app_port
  db_port  = local.db_port
}

module "edge" {
  source = "../../modules/edge"

  name                  = local.name
  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  alb_security_group_id = module.security_groups.alb_security_group_id
  app_port              = local.app_port
  domain_name           = var.domain_name
  app_subdomain         = var.app_subdomain
  deletion_protection   = var.deletion_protection
  waf_rate_limit        = var.waf_rate_limit
  waf_rate_limit_action = var.waf_rate_limit_action
  kms_key_arn           = module.kms.key_arn
  log_retention_days    = var.log_retention_days
}

module "database" {
  source = "../../modules/database"

  name                 = local.name
  data_subnet_ids      = module.network.data_subnet_ids
  db_security_group_id = module.security_groups.db_security_group_id
  kms_key_arn          = module.kms.key_arn
  instance_class       = var.db_instance_class
  multi_az             = var.db_multi_az
  db_port              = local.db_port
  deletion_protection  = var.deletion_protection
  skip_final_snapshot  = var.db_skip_final_snapshot
  log_retention_days   = var.log_retention_days
}

module "app" {
  source = "../../modules/app"

  name                     = local.name
  aws_region               = var.aws_region
  app_subnet_ids           = module.network.app_subnet_ids
  app_security_group_id    = module.security_groups.app_security_group_id
  target_group_arn         = module.edge.target_group_arn
  alb_resource_label       = module.edge.alb_resource_label
  https_enabled            = module.edge.https_enabled
  kms_key_arn              = module.kms.key_arn
  container_image          = var.container_image
  app_port                 = local.app_port
  task_cpu                 = var.task_cpu
  task_memory              = var.task_memory
  db_host                  = module.database.address
  db_port                  = module.database.port
  db_name                  = module.database.db_name
  db_secret_arn            = module.database.master_user_secret_arn
  min_capacity             = var.min_capacity
  max_capacity             = var.max_capacity
  cpu_target_percent       = var.cpu_target_percent
  requests_per_target      = var.requests_per_target
  enable_scheduled_scaling = var.enable_scheduled_scaling
  enable_execute_command   = var.enable_execute_command
  log_retention_days       = var.log_retention_days

  # The target group must be attached to a listener before ECS registers tasks.
  depends_on = [module.edge]
}

module "observability" {
  source = "../../modules/observability"

  name                    = local.name
  aws_region              = var.aws_region
  kms_key_arn             = module.kms.key_arn
  alert_email             = var.alert_email
  alb_arn_suffix          = module.edge.alb_arn_suffix
  target_group_arn_suffix = module.edge.target_group_arn_suffix
  cluster_name            = module.app.cluster_name
  service_name            = module.app.service_name
  db_identifier           = module.database.identifier
  web_acl_name            = module.edge.web_acl_name
  cpu_target_percent      = var.cpu_target_percent
}
