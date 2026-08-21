variable "secret_name" {
  description = "Name of the Secrets Manager secret"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
