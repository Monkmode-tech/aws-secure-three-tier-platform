###############################################################################
# Database module
#
# RDS for MariaDB in the isolated data subnets:
#   - Multi-AZ standby (synchronous replication, automatic failover)
#   - Storage and the master-credential secret encrypted with the env KMS key
#   - Master password generated and stored by RDS in Secrets Manager; it never
#     appears in Terraform variables, tfvars files or the task definition
#   - Error and slow-query logs exported to KMS-encrypted CloudWatch Logs
###############################################################################

locals {
  identifier = "${var.name}-db"
}

resource "aws_db_subnet_group" "this" {
  name        = "${var.name}-db"
  description = "Isolated data-tier subnets for ${var.name}"
  subnet_ids  = var.data_subnet_ids

  tags = { Name = "${var.name}-db-subnets" }
}

resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.name}-"
  family      = var.parameter_group_family
  description = "MariaDB parameters for ${var.name}"

  parameter {
    name  = "slow_query_log"
    value = "1"
  }

  parameter {
    name  = "long_query_time"
    value = "2"
  }

  parameter {
    name  = "log_output"
    value = "FILE"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Pre-create the export log groups so they are KMS-encrypted and have a
# retention policy (RDS would otherwise create them unencrypted, never expiring).
resource "aws_cloudwatch_log_group" "rds" {
  for_each = toset(var.cloudwatch_logs_exports)

  name              = "/aws/rds/instance/${local.identifier}/${each.key}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

# Enhanced Monitoring: OS-level metrics (per-process CPU, memory, disk I/O).
data "aws_iam_policy_document" "monitoring_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  name               = "${var.name}-rds-monitoring"
  assume_role_policy = data.aws_iam_policy_document.monitoring_assume.json
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "random_id" "final_snapshot" {
  byte_length = 4
}

resource "aws_db_instance" "this" {
  identifier     = local.identifier
  engine         = "mariadb"
  engine_version = var.engine_version
  instance_class = var.instance_class
  port           = var.db_port
  db_name        = var.db_name
  username       = var.master_username

  manage_master_user_password   = true
  master_user_secret_kms_key_id = var.kms_key_arn

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  multi_az               = var.multi_az
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.db_security_group_id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false

  backup_retention_period    = var.backup_retention_days
  backup_window              = "07:00-08:00"
  maintenance_window         = "sun:08:30-sun:09:30"
  copy_tags_to_snapshot      = true
  auto_minor_version_upgrade = true
  deletion_protection        = var.deletion_protection
  skip_final_snapshot        = var.skip_final_snapshot
  final_snapshot_identifier  = var.skip_final_snapshot ? null : "${local.identifier}-final-${random_id.final_snapshot.hex}"
  apply_immediately          = var.apply_immediately

  enabled_cloudwatch_logs_exports = var.cloudwatch_logs_exports
  monitoring_interval             = var.monitoring_interval
  monitoring_role_arn             = var.monitoring_interval > 0 ? aws_iam_role.monitoring[0].arn : null

  tags = { Name = local.identifier }

  depends_on = [aws_cloudwatch_log_group.rds, aws_iam_role_policy_attachment.monitoring]
}
