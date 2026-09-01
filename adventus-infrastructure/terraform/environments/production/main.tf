terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "production"
      ManagedBy   = "terraform"
    }
  }
}

locals {
  tags = {
    Project     = var.project_name
    Environment = "production"
  }
}

# =============================================================================
# Modules
# =============================================================================

module "networking" {
  source = "../../modules/networking"

  project_name = var.project_name
  vpc_cidr     = var.vpc_cidr
  tags         = local.tags
}

module "ecr" {
  source = "../../modules/ecr"

  repository_name = var.project_name
  tags            = local.tags
}

module "security_groups" {
  source = "../../modules/security-groups"

  project_name = var.project_name
  vpc_id       = module.networking.vpc_id
  tags         = local.tags
}

module "secrets" {
  source = "../../modules/secrets"

  secret_name = "${var.project_name}/app"
  tags        = local.tags
}

module "iam" {
  source = "../../modules/iam"

  project_name       = var.project_name
  ecr_repository_arn = module.ecr.repository_arn
  secrets_arn        = module.secrets.secret_arn
  tags               = local.tags
}

module "alb" {
  source = "../../modules/alb"

  project_name      = var.project_name
  vpc_id            = module.networking.vpc_id
  public_subnet_ids = module.networking.public_subnet_ids
  security_group_id = module.security_groups.alb_security_group_id
  tags              = local.tags
}

module "rds" {
  source = "../../modules/rds"

  project_name            = var.project_name
  private_subnet_ids      = module.networking.private_subnet_ids
  security_group_id       = module.security_groups.rds_security_group_id
  instance_class          = var.db_instance_class
  allocated_storage       = var.db_allocated_storage
  db_name                 = "adventus"
  db_username             = "adventus_admin"
  db_password             = var.db_password
  skip_final_snapshot     = var.db_skip_final_snapshot
  backup_retention_period = var.db_backup_retention_period
  tags                    = local.tags
}

module "bastion" {
  source = "../../modules/bastion"

  project_name      = var.project_name
  subnet_id         = module.networking.private_subnet_ids[0]
  security_group_id = module.security_groups.bastion_security_group_id
  tags              = local.tags
}

module "iam_developers" {
  source = "../../modules/iam-developers"

  project_name         = var.project_name
  bastion_instance_arn = module.bastion.instance_arn
  developer_user_names = var.developer_user_names
  tags                 = local.tags
}

module "ecs" {
  source = "../../modules/ecs"

  project_name          = var.project_name
  aws_region            = var.aws_region
  task_cpu              = var.task_cpu
  task_memory           = var.task_memory
  desired_count         = var.desired_count
  ecr_repository_url    = module.ecr.repository_url
  execution_role_arn    = module.iam.ecs_task_execution_role_arn
  task_role_arn         = module.iam.ecs_task_role_arn
  secrets_arn           = module.secrets.secret_arn
  alb_dns_name          = module.alb.alb_dns_name
  app_env               = "production"
  run_migrations        = var.run_migrations
  private_subnet_ids    = module.networking.private_subnet_ids
  ecs_security_group_id = module.security_groups.ecs_security_group_id
  target_group_arn      = module.alb.target_group_arn
  log_retention_days    = var.log_retention_days
  container_insights    = var.container_insights
  tags                  = local.tags
}
