aws_region         = "ap-southeast-1"
task_cpu           = 512
task_memory        = 1024
desired_count      = 2
log_retention_days = 90
container_insights = true

# RDS
db_instance_class          = "db.t3.small"
db_allocated_storage       = 20
db_skip_final_snapshot     = false
db_backup_retention_period = 7
