output "instance_id" {
  description = "Bastion EC2 instance ID (target for `aws ssm start-session`)"
  value       = aws_instance.this.id
}

output "instance_arn" {
  description = "Bastion EC2 instance ARN (used to scope developer IAM policies)"
  value       = aws_instance.this.arn
}
