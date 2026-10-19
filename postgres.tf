# DB Subnet Group
resource "aws_db_subnet_group" "private" {
  count       = var.enable_postgres ? 1 : 0
  name        = var.db_subnet_group_name
  subnet_ids  = var.private_subnets
  description = var.subnet_group_description
}

# Security Group for PostgreSQL
resource "aws_security_group" "db_sg" {
  count       = var.enable_postgres ? 1 : 0
  name        = var.db_security_group_name
  description = var.db_security_group_description
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.postgres_ingress_rules
    content {
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = var.tags
}

locals {
  postgres_major_version = split(".", var.postgres_version)[0]

  # Baseline parameters, then var.postgres_parameters on top (same name wins).
  # An override of shared_preload_libraries must keep pgaudit in the list.
  postgres_parameters = values(merge(
    {
      shared_preload_libraries = { name = "shared_preload_libraries", value = "pg_stat_statements,pgaudit", apply_method = "pending-reboot" }
      "pgaudit.log"            = { name = "pgaudit.log", value = var.postgres_pgaudit_log_classes, apply_method = "immediate" }
    },
    { for p in var.postgres_parameters : p.name => p }
  ))
}

# RDS PostgreSQL Instance
module "postgresql" {
  count          = var.enable_postgres ? 1 : 0
  source         = "terraform-aws-modules/rds/aws"
  version        = "~> 6.0"
  identifier     = var.db_identifier
  engine         = "postgres"
  engine_version = var.postgres_version
  family         = "postgres${local.postgres_major_version}"

  instance_class        = var.instance_class
  allocated_storage     = var.allocated_storage
  storage_type          = var.storage_type
  max_allocated_storage = var.max_allocated_storage
  iops                  = var.iops
  multi_az              = false
  publicly_accessible   = false
  storage_encrypted     = true


  db_name  = var.db_name
  username = var.username
  password = jsondecode(data.aws_secretsmanager_secret_version.postgres[0].secret_string).password
  port     = 5432

  vpc_security_group_ids = [aws_security_group.db_sg[0].id]
  db_subnet_group_name   = aws_db_subnet_group.private[0].name

  backup_retention_period               = var.backup_retention_period
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_retention_period
  allow_major_version_upgrade           = var.allow_major_version_upgrade
  apply_immediately                     = var.apply_immediately
  backup_window                         = var.backup_window
  copy_tags_to_snapshot                 = var.copy_tags_to_snapshot
  maintenance_window                    = var.maintenance_window
  manage_master_user_password           = var.manage_master_user_password
  skip_final_snapshot                   = var.skip_final_snapshot

  # pgaudit (SOC 2: Vanta "RDS for PostgreSQL ... pgaudit auditing enabled").
  # The module owns the parameter group so pgaudit can't drift off a
  # hand-made group. shared_preload_libraries is static: the instance shows
  # pending-reboot until its next reboot, and only then does pgaudit load.
  create_db_parameter_group       = var.manage_postgres_parameter_group
  parameter_group_name            = var.manage_postgres_parameter_group ? "${var.db_identifier}-pg${local.postgres_major_version}" : var.parameter_group_name
  parameter_group_use_name_prefix = true
  parameters                      = local.postgres_parameters

  # Ship the postgresql log (which carries the pgaudit records) to CloudWatch.
  enabled_cloudwatch_logs_exports        = var.postgres_cloudwatch_logs_exports
  create_cloudwatch_log_group            = length(var.postgres_cloudwatch_logs_exports) > 0
  cloudwatch_log_group_retention_in_days = var.postgres_log_retention_in_days
  tags                                   = var.tags
}
