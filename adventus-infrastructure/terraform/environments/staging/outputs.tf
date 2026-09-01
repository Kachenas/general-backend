output "alb_dns_name" {
  description = "DNS name of the ALB"
  value       = module.alb.alb_dns_name
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = module.ecr.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs.cluster_name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = module.ecs.service_name
}

output "ecs_task_definition_family" {
  description = "ECS task definition family"
  value       = module.ecs.task_definition_family
}

output "ecs_container_name" {
  description = "ECS container name"
  value       = module.ecs.container_name
}

output "rds_endpoint" {
  description = "RDS endpoint (host:port)"
  value       = module.rds.db_endpoint
}

output "rds_host" {
  description = "RDS hostname"
  value       = module.rds.db_host
}

output "bastion_instance_id" {
  description = "Bastion EC2 instance ID (use with `aws ssm start-session` to tunnel to RDS)"
  value       = module.bastion.instance_id
}

output "developer_ssm_policy_arn" {
  description = "IAM policy ARN granting bastion SSM access — attach to an Identity Center permission set if not using developer_user_names"
  value       = module.iam_developers.policy_arn
}

output "developer_group_name" {
  description = "IAM group name developers are added to for bastion SSM access"
  value       = module.iam_developers.developer_group_name
}
