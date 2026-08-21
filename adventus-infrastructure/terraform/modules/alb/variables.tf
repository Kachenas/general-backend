variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the target group"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for the ALB"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID for the ALB"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
