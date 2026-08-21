variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "ecr_repository_arn" {
  description = "ARN of the ECR repository for pull permissions"
  type        = string
}

variable "secrets_arn" {
  description = "ARN of the Secrets Manager secret"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
