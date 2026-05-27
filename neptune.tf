# Neptune Serverless cluster — graph store for knowledge-hub and similar workloads.
# IAM database authentication is enabled so pods authenticate via their Pod
# Identity role (no static credentials). Workload-specific connect permissions
# live on the role in nx-iam-tf, scoped to this cluster's resource ID.

resource "aws_neptune_subnet_group" "this" {
  count       = var.enable_neptune ? 1 : 0
  name        = var.neptune_subnet_group_name
  subnet_ids  = var.private_subnets
  description = "Subnet group for ${var.neptune_cluster_identifier}"
  tags        = var.tags
}

resource "aws_security_group" "neptune" {
  count       = var.enable_neptune ? 1 : 0
  name        = var.neptune_security_group_name
  description = "Allow Neptune (8182) access"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 8182
    to_port     = 8182
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
    description = "Neptune endpoint access from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

resource "aws_neptune_cluster" "this" {
  count                               = var.enable_neptune ? 1 : 0
  cluster_identifier                  = var.neptune_cluster_identifier
  engine                              = "neptune"
  engine_version                      = var.neptune_engine_version
  neptune_subnet_group_name           = aws_neptune_subnet_group.this[0].name
  vpc_security_group_ids              = [aws_security_group.neptune[0].id]
  storage_encrypted                   = true
  iam_database_authentication_enabled = true
  backup_retention_period             = var.neptune_backup_retention_period
  preferred_backup_window             = var.neptune_backup_window
  preferred_maintenance_window        = var.neptune_maintenance_window
  skip_final_snapshot                 = var.neptune_skip_final_snapshot
  apply_immediately                   = var.neptune_apply_immediately
  deletion_protection                 = var.neptune_deletion_protection

  serverless_v2_scaling_configuration {
    min_capacity = var.neptune_min_ncu
    max_capacity = var.neptune_max_ncu
  }

  tags = var.tags
}

resource "aws_neptune_cluster_instance" "this" {
  count              = var.enable_neptune ? var.neptune_instance_count : 0
  identifier         = "${var.neptune_cluster_identifier}-${count.index + 1}"
  cluster_identifier = aws_neptune_cluster.this[0].id
  engine             = "neptune"
  instance_class     = "db.serverless"
  apply_immediately  = var.neptune_apply_immediately
  tags               = var.tags
}

# Neptune IAM-auth policy attached to the knowledge-hub role.
# Lives here (not in nx-iam-tf) because the policy resource ARN depends on
# aws_neptune_cluster.this[0].cluster_resource_id, which only exists after
# Neptune is provisioned. Pulling this into nx-iam-tf would create a cycle.

resource "aws_iam_policy" "neptune_connect" {
  count = var.enable_neptune && var.enable_knowledge_hub_pod_identity ? 1 : 0
  name  = "${var.neptune_cluster_identifier}-connect"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "NeptuneDataAccess"
        Effect = "Allow"
        Action = [
          "neptune-db:connect",
          "neptune-db:ReadDataViaQuery",
          "neptune-db:WriteDataViaQuery",
          "neptune-db:DeleteDataViaQuery",
          "neptune-db:GetEngineStatus",
          "neptune-db:GetQueryStatus"
        ]
        Resource = "arn:aws:neptune-db:${var.region}:${data.aws_caller_identity.current.account_id}:${aws_neptune_cluster.this[0].cluster_resource_id}/*"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "knowledge_hub_neptune" {
  # count uses only plan-time-known vars; consumer must pass a real role ARN
  # when enable_knowledge_hub_pod_identity is true, else the split fails at apply.
  count      = var.enable_neptune && var.enable_knowledge_hub_pod_identity ? 1 : 0
  role       = split("/", var.knowledge_hub_role_arn)[1]
  policy_arn = aws_iam_policy.neptune_connect[0].arn
}
