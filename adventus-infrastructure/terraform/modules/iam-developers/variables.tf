variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "bastion_instance_arn" {
  description = "ARN of the bastion EC2 instance developers are allowed to open SSM sessions to"
  type        = string
}

variable "developer_user_names" {
  description = "Existing IAM user names to add to the developers group. Leave empty and attach `policy_arn` elsewhere (e.g. an Identity Center permission set) if not using IAM users directly."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
