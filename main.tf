locals {
  name = "${var.project_name}-${var.environment}"
  tags = {
    Project = var.project_name, Environment = var.environment, ManagedBy = "Terraform"
  }
}

data "aws_ssm_parameter" "vpc_id" {
  name = "/${var.project_name}/${var.environment}/network/vpc-id"
}

data "aws_ssm_parameter" "private_subnet_ids" {
  name = "/${var.project_name}/${var.environment}/network/private-subnet-ids"
}

data "aws_ssm_parameter" "eks_node_security_group_id" {
  name = "/${var.project_name}/${var.environment}/eks/node-security-group-id"
}

resource "aws_db_subnet_group" "main" {
  name       = "${local.name}-db"
  subnet_ids = jsondecode(data.aws_ssm_parameter.private_subnet_ids.value)
}

resource "aws_security_group" "database" {
  name_prefix = "${local.name}-postgres-"
  description = "PostgreSQL acessivel apenas pelos workloads autorizados"
  vpc_id      = data.aws_ssm_parameter.vpc_id.value
  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_ingress_rule" "eks" {
  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = data.aws_ssm_parameter.eks_node_security_group_id.value
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "Aplicacao no EKS"
}

resource "aws_vpc_security_group_egress_rule" "database" {
  security_group_id = aws_security_group.database.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_db_instance" "postgres" {
  identifier                  = "${local.name}-postgres"
  engine                      = "postgres"
  engine_version              = var.engine_version
  instance_class              = var.instance_class
  allocated_storage           = var.allocated_storage
  max_allocated_storage       = var.max_allocated_storage
  storage_type                = "gp3"
  storage_encrypted           = true
  db_name                     = var.database_name
  username                    = var.master_username
  manage_master_user_password = true
  port                        = 5432
  db_subnet_group_name        = aws_db_subnet_group.main.name
  vpc_security_group_ids      = [aws_security_group.database.id]
  publicly_accessible         = false
  multi_az                    = var.multi_az
  backup_retention_period     = var.backup_retention_period
  copy_tags_to_snapshot       = true
  auto_minor_version_upgrade  = true
  deletion_protection         = var.deletion_protection
  skip_final_snapshot         = false
  final_snapshot_identifier   = "${local.name}-postgres-final"
  apply_immediately           = false
}

resource "aws_ssm_parameter" "database" {
  for_each = {
    "/${var.project_name}/${var.environment}/database/endpoint"          = aws_db_instance.postgres.address
    "/${var.project_name}/${var.environment}/database/port"              = tostring(aws_db_instance.postgres.port)
    "/${var.project_name}/${var.environment}/database/name"              = var.database_name
    "/${var.project_name}/${var.environment}/database/security-group-id" = aws_security_group.database.id
    "/${var.project_name}/${var.environment}/database/master-secret-arn" = aws_db_instance.postgres.master_user_secret[0].secret_arn
  }
  name  = each.key
  type  = "String"
  value = each.value
}

