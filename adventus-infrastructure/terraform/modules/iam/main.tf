# =============================================================================
# ECS Task Execution Role
# =============================================================================
# Used by the ECS agent to pull images from ECR and read secrets from
# Secrets Manager. This is NOT the role the application code runs as.

data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name               = "${var.project_name}-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "task_execution_custom" {
  # Allow pulling images from the specific ECR repository
  statement {
    sid = "ECRPull"
    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
    ]
    resources = [var.ecr_repository_arn]
  }

  statement {
    sid       = "ECRAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Allow reading application secrets from Secrets Manager
  statement {
    sid = "SecretsManagerRead"
    actions = [
      "secretsmanager:GetSecretValue",
    ]
    resources = [var.secrets_arn]
  }
}

resource "aws_iam_role_policy" "task_execution_custom" {
  name   = "${var.project_name}-task-execution-policy"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.task_execution_custom.json
}

# =============================================================================
# ECS Task Role
# =============================================================================
# The role that the application container runs as. Start with no extra
# permissions; add policies here as the app needs AWS services (S3, SQS, etc).

resource "aws_iam_role" "task" {
  name               = "${var.project_name}-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json

  tags = var.tags
}
