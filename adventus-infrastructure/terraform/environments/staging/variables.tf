variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-1"
}

variable "project_name" {
  description = "Project name used for all resource naming"
  type        = string
  default     = "adventus-staging"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "task_cpu" {
  description = "CPU units for the Fargate task"
  type        = number
}

variable "task_memory" {
  description = "Memory (MiB) for the Fargate task"
  type        = number
}

variable "desired_count" {
  description = "Number of ECS task instances"
  type        = number
}

variable "run_migrations" {
  description = "Whether to run migrations on container start"
  type        = string
  default     = "true"
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
}

variable "container_insights" {
  description = "Enable Container Insights on the ECS cluster"
  type        = bool
  default     = false
}

variable "db_password" {
  description = "Master password for the RDS database"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 20
}
