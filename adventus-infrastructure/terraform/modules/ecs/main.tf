# =============================================================================
# CloudWatch Log Group
# =============================================================================

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# =============================================================================
# ECS Cluster
# =============================================================================

resource "aws_ecs_cluster" "this" {
  name = var.project_name

  setting {
    name  = "containerInsights"
    value = var.container_insights ? "enabled" : "disabled"
  }

  tags = var.tags
}

# =============================================================================
# ECS Task Definition
# =============================================================================

resource "aws_ecs_task_definition" "this" {
  family                   = var.project_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([
    {
      name      = var.project_name
      image     = "${var.ecr_repository_url}:latest"
      essential = true

      portMappings = [
        {
          containerPort = 80
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "APP_ENV", value = var.app_env },
        { name = "APP_DEBUG", value = "false" },
        { name = "APP_URL", value = "http://${var.alb_dns_name}" },
        { name = "LOG_CHANNEL", value = "stderr" },
        { name = "DB_CONNECTION", value = "pgsql" },
        { name = "DB_SSLMODE", value = "require" },
        { name = "RUN_MIGRATIONS", value = var.run_migrations },
      ]

      secrets = [
        { name = "APP_KEY", valueFrom = "${var.secrets_arn}:APP_KEY::" },
        { name = "DB_HOST", valueFrom = "${var.secrets_arn}:DB_HOST::" },
        { name = "DB_PORT", valueFrom = "${var.secrets_arn}:DB_PORT::" },
        { name = "DB_DATABASE", valueFrom = "${var.secrets_arn}:DB_DATABASE::" },
        { name = "DB_USERNAME", valueFrom = "${var.secrets_arn}:DB_USERNAME::" },
        { name = "DB_PASSWORD", valueFrom = "${var.secrets_arn}:DB_PASSWORD::" },
        { name = "PASSPORT_PRIVATE_KEY", valueFrom = "${var.secrets_arn}:PASSPORT_PRIVATE_KEY::" },
        { name = "PASSPORT_PUBLIC_KEY", valueFrom = "${var.secrets_arn}:PASSPORT_PUBLIC_KEY::" },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = var.tags
}

# =============================================================================
# ECS Service (Fargate)
# =============================================================================

resource "aws_ecs_service" "this" {
  name            = var.project_name
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = var.project_name
    container_port   = 80
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # CI/CD updates the task definition with new image tags. Terraform must
  # not revert the task definition to the one it last applied.
  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = var.tags
}
