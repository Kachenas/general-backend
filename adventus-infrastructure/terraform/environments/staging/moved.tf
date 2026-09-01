# =============================================================================
# Preserves resource identity across the security-groups module extraction so
# `terraform apply` moves these in state instead of destroying and recreating
# live security groups still attached to the ALB, ECS tasks, and RDS.
#
# Safe to keep indefinitely; a `moved` block is a no-op if the "from" address
# was never in state (e.g. the bastion, applied for the first time alongside
# this refactor).
# =============================================================================

moved {
  from = module.networking.aws_security_group.alb
  to   = module.security_groups.aws_security_group.alb
}

moved {
  from = module.networking.aws_vpc_security_group_ingress_rule.alb_http
  to   = module.security_groups.aws_vpc_security_group_ingress_rule.alb_http
}

moved {
  from = module.networking.aws_vpc_security_group_egress_rule.alb_all
  to   = module.security_groups.aws_vpc_security_group_egress_rule.alb_all
}

moved {
  from = module.networking.aws_security_group.ecs
  to   = module.security_groups.aws_security_group.ecs
}

moved {
  from = module.networking.aws_vpc_security_group_ingress_rule.ecs_from_alb
  to   = module.security_groups.aws_vpc_security_group_ingress_rule.ecs_from_alb
}

moved {
  from = module.networking.aws_vpc_security_group_egress_rule.ecs_all
  to   = module.security_groups.aws_vpc_security_group_egress_rule.ecs_all
}

moved {
  from = module.rds.aws_security_group.rds
  to   = module.security_groups.aws_security_group.rds
}

moved {
  from = module.rds.aws_vpc_security_group_ingress_rule.rds_from_ecs
  to   = module.security_groups.aws_vpc_security_group_ingress_rule.rds_from_ecs
}

moved {
  from = module.rds.aws_vpc_security_group_egress_rule.rds_all
  to   = module.security_groups.aws_vpc_security_group_egress_rule.rds_all
}

moved {
  from = aws_vpc_security_group_ingress_rule.rds_from_bastion
  to   = module.security_groups.aws_vpc_security_group_ingress_rule.rds_from_bastion
}

moved {
  from = module.bastion.aws_security_group.this
  to   = module.security_groups.aws_security_group.bastion
}

moved {
  from = module.bastion.aws_vpc_security_group_egress_rule.all
  to   = module.security_groups.aws_vpc_security_group_egress_rule.bastion_all
}
