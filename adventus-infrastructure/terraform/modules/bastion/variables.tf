variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the bastion (a private subnet, reached via NAT for SSM endpoints)"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID to attach to the bastion (owned by modules/security-groups)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the bastion"
  type        = string
  default     = "t3.micro"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
