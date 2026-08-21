variable "project_name" {
  description = "Project name used for resource naming and ECS naming"
  type        = string
}

variable "aws_region" {
  description = "AWS region for CloudWatch log configuration"
  type        = string
}

variable "task_cpu" {
  description = "CPU units for the Fargate task (256, 512, 1024, 2048, 4096)"
  type        = number
}

variable "task_memory" {
  description = "Memory (MiB) for the Fargate task"
  type        = number
}

variable "desired_count" {
  description = "Number of task instances to run"
  type        = number
  default     = 1
}

variable "ecr_repository_url" {
  description = "ECR repository URL for the container image"
  type        = string
}

variable "execution_role_arn" {
  description = "ARN of the ECS task execution role"
  type        = string
}

variable "task_role_arn" {
  description = "ARN of the ECS task role"
  type        = string
}

variable "secrets_arn" {
  description = "ARN of the Secrets Manager secret for app secrets"
  type        = string
}

variable "alb_dns_name" {
  description = "DNS name of the ALB for APP_URL"
  type        = string
}

variable "app_env" {
  description = "Laravel APP_ENV value (staging, production)"
  type        = string
}

variable "run_migrations" {
  description = "Whether to run migrations on container start"
  type        = string
  default     = "false"
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "ecs_security_group_id" {
  description = "Security group ID for ECS tasks"
  type        = string
}

variable "target_group_arn" {
  description = "ALB target group ARN"
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14
}

variable "container_insights" {
  description = "Enable Container Insights on the ECS cluster"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
