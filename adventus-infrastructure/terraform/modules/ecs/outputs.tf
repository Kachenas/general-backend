output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.this.name
}

output "service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.this.name
}

output "task_definition_family" {
  description = "Family of the ECS task definition"
  value       = aws_ecs_task_definition.this.family
}

output "container_name" {
  description = "Name of the container in the task definition"
  value       = var.project_name
}
