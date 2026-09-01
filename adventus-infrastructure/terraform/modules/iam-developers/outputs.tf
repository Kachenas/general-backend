output "policy_arn" {
  description = "IAM policy ARN — attach to an Identity Center permission set if not using IAM users"
  value       = aws_iam_policy.ssm_bastion_access.arn
}

output "developer_group_name" {
  description = "IAM group name developers are added to for bastion SSM access"
  value       = aws_iam_group.developers.name
}
