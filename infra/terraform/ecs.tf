# ── ECS Fargate — cluster, task definitions, services, ALB, autoscaling ─────

locals {
  # Common non-secret environment injected into every task.
  common_env = [
    { name = "ENVIRONMENT",        value = var.environment },
    { name = "APP_NAME",           value = "Hyperlocal Customer API" },
    { name = "REDIS_URL",          value = "redis://${local.redis_endpoint}:6379/0" },
    { name = "CELERY_BROKER_URL",  value = "redis://${local.redis_endpoint}:6379/1" },
    { name = "CELERY_RESULT_BACKEND", value = "redis://${local.redis_endpoint}:6379/2" },
    { name = "USE_AWS_SECRETS",    value = tostring(var.use_aws_secrets) },
    { name = "AWS_REGION",         value = var.aws_region },
    { name = "AWS_SECRETS_SECRET_ID", value = "${var.secrets_secret_name}/${var.environment}" },
    { name = "STORAGE_PROVIDER",   value = "s3" },
    { name = "S3_BUCKET_NAME",     value = aws_s3_bucket.uploads.id },
    { name = "S3_REGION",          value = var.aws_region },
    { name = "S3_ACL",             value = "private" },
    { name = "LOG_LEVEL",          value = "INFO" },
    { name = "LOG_FORMAT",         value = "json" },
    { name = "FRONTEND_URL",       value = "https://${var.api_subdomain}.${var.domain_name}" },
    { name = "CORS_ORIGINS",       value = "https://${var.api_subdomain}.${var.domain_name}" },
    { name = "DEBUG",              value = tostring(!var.is_production) },
  ]
  # RDS connection string — AWS-native injection (never in env/source).
  db_secret_json = "${aws_secretsmanager_secret.database.arn}:DATABASE_URL::"
  logs_prefix    = "/ecs/${local.name_prefix}"
}

resource "aws_cloudwatch_log_group" "all" {
  name              = local.logs_prefix
  retention_in_days = 30
  tags              = { Name = "${local.name_prefix}-logs" }
}

resource "aws_ecs_cluster" "main" {
  name = var.ecs_cluster_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
  tags = { Name = var.ecs_cluster_name }
}

# ── Task definitions (Fargate, awsvpc) ──────────────────────────────────────
locals {
  container_image = "${var.ecr_registry_url}/${var.ecr_repository_name}:${var.backend_image_tag}"

  base_container = {
    essential = true
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.all.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = local.name_prefix
      }
    }
  }
}

resource "aws_ecs_task_definition" "web" {
  family                   = "${local.name_prefix}-web"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.app_cpu
  memory                   = var.app_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn
  container_definitions = jsonencode([
    merge(local.base_container, {
      name  = "api"
      image = local.container_image
      portMappings = [{ containerPort = var.app_port, protocol = "tcp" }]
      environment = concat(local.common_env, [
        { name = "RUN_MIGRATIONS", value = "false" },
      ])
      secrets = [{ name = "DATABASE_URL", valueFrom = local.db_secret_json }]
      healthCheck = {
        command     = ["CMD-SHELL", "curl -fsS http://127.0.0.1:8000/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 90
      }
    })
  ])
  tags = { Name = "${local.name_prefix}-web-task" }
}

# Celery worker task definition
resource "aws_ecs_task_definition" "worker" {
  family                   = "${local.name_prefix}-worker"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.app_cpu
  memory                   = var.app_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn
  container_definitions = jsonencode([
    merge(local.base_container, {
      name  = "worker"
      image = local.container_image
      command = ["celery", "-A", "app.core.celery_app.celery_app",
                 "worker", "--loglevel=info", "--concurrency=1"]
      environment = concat(local.common_env, [
        { name = "RUN_MIGRATIONS", value = "false" },
      ])
      secrets = [{ name = "DATABASE_URL", valueFrom = local.db_secret_json }]
    })
  ])
  tags = { Name = "${local.name_prefix}-worker-task" }
}

# Celery beat (scheduler) task definition
resource "aws_ecs_task_definition" "beat" {
  family                   = "${local.name_prefix}-beat"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn
  container_definitions = jsonencode([
    merge(local.base_container, {
      name  = "beat"
      image = local.container_image
      command = ["celery", "-A", "app.core.celery_app.celery_app",
                 "beat", "--loglevel=info"]
      environment = concat(local.common_env, [
        { name = "RUN_MIGRATIONS", value = "false" },
      ])
      secrets = [{ name = "DATABASE_URL", valueFrom = local.db_secret_json }]
    })
  ])
  tags = { Name = "${local.name_prefix}-beat-task" }
}

# ── ALB ─────────────────────────────────────────────────────────────────────
resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
  tags               = { Name = "${local.name_prefix}-alb" }
}

resource "aws_lb_target_group" "web" {
  name        = "${local.name_prefix}-web-tg"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  health_check {
    path                = "/ready"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200"
  }
  tags = { Name = "${local.name_prefix}-web-tg" }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = local.cert_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# ── Services ────────────────────────────────────────────────────────────────
resource "aws_ecs_service" "web" {
  name            = "${local.name_prefix}-web"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.web.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.web.arn
    container_name   = "api"
    container_port   = var.app_port
  }

  depends_on = [aws_lb_listener.https]
  tags       = { Name = "${local.name_prefix}-web-svc" }
}

resource "aws_ecs_service" "worker" {
  name            = "${local.name_prefix}-worker"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = var.worker_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = false
  }
  tags = { Name = "${local.name_prefix}-worker-svc" }
}

resource "aws_ecs_service" "beat" {
  name            = "${local.name_prefix}-beat"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.beat.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = false
  }
  tags = { Name = "${local.name_prefix}-beat-svc" }
}

# ── Autoscaling (web) ───────────────────────────────────────────────────────
resource "aws_appautoscaling_target" "web" {
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.web.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "web_cpu" {
  name               = "${local.name_prefix}-web-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.web.resource_id
  scalable_dimension = aws_appautoscaling_target.web.scalable_dimension
  service_namespace  = aws_appautoscaling_target.web.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 120
  }
}