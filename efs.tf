################################################################################
# EFS Filesystem for zone-independent persistent storage
# Used by workloads that need persistence but don't require EBS-level IOPS
# (e.g., Valkey cache instances with appendonly enabled)
################################################################################

resource "aws_efs_file_system" "this" {
  count = var.enable_efs ? 1 : 0

  encrypted       = true
  throughput_mode = "elastic"

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-efs"
  })
}

locals {
  efs_ingress_security_group_ids = concat(
    var.efs_restrict_ingress_to_cluster_nodes ? [module.eks.node_security_group_id] : [],
    var.efs_allowed_security_group_ids,
  )
  efs_restrict_ingress = length(local.efs_ingress_security_group_ids) > 0
}

resource "aws_security_group" "efs" {
  count = var.enable_efs ? 1 : 0

  name        = "${var.cluster_name}-efs-sg"
  description = "Allow NFS traffic from VPC for EFS"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = local.efs_restrict_ingress ? [] : [1]
    content {
      description = "NFS from VPC"
      from_port   = 2049
      to_port     = 2049
      protocol    = "tcp"
      cidr_blocks = [var.vpc_cidr_block]
    }
  }

  dynamic "ingress" {
    for_each = local.efs_restrict_ingress ? [1] : []
    content {
      description     = "NFS from allowed security groups"
      from_port       = 2049
      to_port         = 2049
      protocol        = "tcp"
      security_groups = local.efs_ingress_security_group_ids
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-efs-sg"
  })
}

# Without a filesystem policy EFS allows any client that reaches a mount target to mount
# unauthenticated. Default: allow only via mount targets, deny anything not over TLS.
data "aws_iam_policy_document" "efs" {
  count = var.enable_efs && var.enable_efs_file_system_policy && var.efs_file_system_policy == null ? 1 : 0

  statement {
    sid       = "AllowViaMountTarget"
    effect    = "Allow"
    actions   = ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite", "elasticfilesystem:ClientRootAccess"]
    resources = [aws_efs_file_system.this[0].arn]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "elasticfilesystem:AccessedViaMountTarget"
      values   = ["true"]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["*"]
    resources = [aws_efs_file_system.this[0].arn]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_efs_file_system_policy" "this" {
  count = var.enable_efs && var.enable_efs_file_system_policy ? 1 : 0

  file_system_id = aws_efs_file_system.this[0].id
  policy         = coalesce(var.efs_file_system_policy, try(data.aws_iam_policy_document.efs[0].json, null))
}

resource "aws_efs_mount_target" "this" {
  for_each = var.enable_efs ? toset(var.private_subnets) : toset([])

  file_system_id  = aws_efs_file_system.this[0].id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs[0].id]
}

################################################################################
# EFS StorageClass for Kubernetes
################################################################################

resource "kubernetes_storage_class_v1" "efs" {
  count = var.enable_efs ? 1 : 0

  metadata {
    name = "efs-sc"
  }

  storage_provisioner = "efs.csi.aws.com"
  reclaim_policy      = "Delete"
  volume_binding_mode = "Immediate" # EFS is multi-AZ, no need to wait

  parameters = {
    provisioningMode = "efs-ap" # Dynamic provisioning via EFS Access Points
    fileSystemId     = aws_efs_file_system.this[0].id
    directoryPerms   = "700"
    uid              = "1000"
    gid              = "1000"
  }

  depends_on = [aws_efs_mount_target.this]
}
