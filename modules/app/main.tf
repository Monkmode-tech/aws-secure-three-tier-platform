###############################################################################
# App module
#
# WordPress on ECS Fargate in the private app subnets:
#   - No public IPs; reachable only through the ALB security group
#   - DB credentials and WordPress salts injected from Secrets Manager at
#     task start (never stored in the task definition as plain environment)
#   - Deployment circuit breaker with automatic rollback
#   - Target-tracking autoscaling on CPU and on ALB requests per target,
#     plus optional scheduled scaling (carried over from the CLCS 645 capstone)
#   - Optional ECS Exec for shell access without SSH or bastion hosts
###############################################################################

data "aws_caller_identity" "current" {}

locals {
  container_name = "wordpress"

  # WordPress signs auth cookies with these keys. Every task must share the
  # same values or users are logged out whenever the ALB switches tasks.
  wp_salt_keys = [
    "AUTH_KEY", "SECURE_AUTH_KEY", "LOGGED_IN_KEY", "NONCE_KEY",
    "AUTH_SALT", "SECURE_AUTH_SALT", "LOGGED_IN_SALT", "NONCE_SALT",
  ]

  # TLS terminates at the ALB, so tell WordPress the original request was HTTPS.
  wp_config_extra = <<-PHP
    if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
      $_SERVER['HTTPS'] = 'on';
    }
    define('DISALLOW_FILE_EDIT', true);
    define('FORCE_SSL_ADMIN', ${var.https_enabled ? "true" : "false"});
  PHP

  container_secrets = concat(
    [
      { name = "WORDPRESS_DB_USER", valueFrom = "${var.db_secret_arn}:username::" },
      { name = "WORDPRESS_DB_PASSWORD", valueFrom = "${var.db_secret_arn}:password::" },
    ],
    [for k in local.wp_salt_keys : { name = "WORDPRESS_${k}", valueFrom = "${aws_secretsmanager_secret.wp_salts.arn}:${k}::" }],
  )
}

#------------------------------------------------------------------------------
# Cluster and logs
#------------------------------------------------------------------------------
resource "aws_ecs_cluster" "this" {
  name = "${var.name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  # ECS Exec sessions are encrypted with the env key and every session's
  # output is recorded in a KMS-encrypted log group for audit.
  configuration {
    execute_command_configuration {
      kms_key_id = var.kms_key_arn
      logging    = "OVERRIDE"

      log_configuration {
        cloud_watch_encryption_enabled = true
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.exec.name
      }
    }
  }
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.name}/${local.container_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

resource "aws_cloudwatch_log_group" "exec" {
  name              = "/ecs/${var.name}/exec-sessions"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

#------------------------------------------------------------------------------
# WordPress salts (shared by every task)
#------------------------------------------------------------------------------
resource "random_password" "wp_salts" {
  for_each = toset(local.wp_salt_keys)

  length           = 64
  special          = true
  override_special = "!#%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "wp_salts" {
  name_prefix             = "${var.name}/wordpress-salts-"
  description             = "WordPress authentication keys and salts for ${var.name}"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = var.secret_recovery_window_days
}

resource "aws_secretsmanager_secret_version" "wp_salts" {
  secret_id     = aws_secretsmanager_secret.wp_salts.id
  secret_string = jsonencode({ for k, v in random_password.wp_salts : k => v.result })
}

#------------------------------------------------------------------------------
# IAM
#------------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

# Execution role: used by the ECS agent to pull the image, write logs and
# fetch the two secrets. Scoped to exactly those secret ARNs and the env key.
resource "aws_iam_role" "execution" {
  name               = "${var.name}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "execution_secrets" {
  statement {
    sid       = "ReadAppSecrets"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.db_secret_arn, aws_secretsmanager_secret.wp_salts.arn]
  }

  statement {
    sid       = "DecryptAppSecrets"
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  name   = "read-app-secrets"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_secrets.json
}

# Task role: what the running container may call. WordPress needs no AWS APIs,
# so it only gets permissions when ECS Exec is switched on.
resource "aws_iam_role" "task" {
  name               = "${var.name}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

data "aws_iam_policy_document" "task_exec" {
  statement {
    sid = "EcsExecChannels"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "EcsExecSessionEncryption"
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn]
  }

  statement {
    sid       = "EcsExecSessionLogging"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.exec.arn}:*"]
  }

  statement {
    sid       = "EcsExecFindLogGroup"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:*"]
  }
}

resource "aws_iam_role_policy" "task_exec" {
  count = var.enable_execute_command ? 1 : 0

  name   = "ecs-exec"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_exec.json
}

#------------------------------------------------------------------------------
# Task definition and service
#------------------------------------------------------------------------------
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.name}-${local.container_name}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  container_definitions = jsonencode([
    {
      name      = local.container_name
      image     = var.container_image
      essential = true

      portMappings = [
        { name = "http", containerPort = var.app_port, protocol = "tcp", appProtocol = "http" },
      ]

      environment = [
        { name = "WORDPRESS_DB_HOST", value = "${var.db_host}:${var.db_port}" },
        { name = "WORDPRESS_DB_NAME", value = var.db_name },
        { name = "WORDPRESS_CONFIG_EXTRA", value = local.wp_config_extra },
      ]

      secrets = local.container_secrets

      linuxParameters = {
        initProcessEnabled = true
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = local.container_name
        }
      }
    },
  ])

  depends_on = [aws_secretsmanager_secret_version.wp_salts]
}

resource "aws_ecs_service" "app" {
  name                              = "${var.name}-${local.container_name}"
  cluster                           = aws_ecs_cluster.this.id
  task_definition                   = aws_ecs_task_definition.app.arn
  desired_count                     = var.min_capacity
  launch_type                       = "FARGATE"
  platform_version                  = "LATEST"
  enable_execute_command            = var.enable_execute_command
  health_check_grace_period_seconds = 120
  propagate_tags                    = "SERVICE"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.app_subnet_ids
    security_groups  = [var.app_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = local.container_name
    container_port   = var.app_port
  }

  # Autoscaling owns desired_count after creation.
  lifecycle {
    ignore_changes = [desired_count]
  }
}

#------------------------------------------------------------------------------
# Autoscaling
#------------------------------------------------------------------------------
resource "aws_appautoscaling_target" "ecs" {
  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.app.name}"
  min_capacity       = var.min_capacity
  max_capacity       = var.max_capacity
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.name}-cpu-target-tracking"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  resource_id        = aws_appautoscaling_target.ecs.resource_id

  target_tracking_scaling_policy_configuration {
    target_value       = var.cpu_target_percent
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

resource "aws_appautoscaling_policy" "requests" {
  name               = "${var.name}-requests-target-tracking"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  resource_id        = aws_appautoscaling_target.ecs.resource_id

  target_tracking_scaling_policy_configuration {
    target_value       = var.requests_per_target
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = var.alb_resource_label
    }
  }
}

# Scheduled scaling: shrink overnight, restore before business hours.
resource "aws_appautoscaling_scheduled_action" "night" {
  count = var.enable_scheduled_scaling ? 1 : 0

  name               = "${var.name}-scale-in-night"
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  schedule           = "cron(0 22 * * ? *)"
  timezone           = var.schedule_timezone

  scalable_target_action {
    min_capacity = 1
    max_capacity = var.max_capacity
  }
}

resource "aws_appautoscaling_scheduled_action" "morning" {
  count = var.enable_scheduled_scaling ? 1 : 0

  name               = "${var.name}-scale-out-morning"
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  schedule           = "cron(0 7 * * ? *)"
  timezone           = var.schedule_timezone

  scalable_target_action {
    min_capacity = var.min_capacity
    max_capacity = var.max_capacity
  }

  # Two scheduled actions on one target must not be written concurrently.
  depends_on = [aws_appautoscaling_scheduled_action.night]
}
