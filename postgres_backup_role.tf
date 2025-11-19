# Trust policy document for Postgres Backup (RDS service principal)
# Only created when IRSA is NOT enabled (IAM module handles it when IRSA is enabled)
data "aws_iam_policy_document" "postgres_backup_trust" {
  count = var.enable_irsa && var.enable_postgres ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }
  }
}

# IAM policy for Postgres backup - includes S3 and RDS permissions
data "aws_iam_policy_document" "postgres_backup_policy" {
  count = var.enable_irsa && var.enable_postgres ? 1 : 0

  # S3 bucket permissions for backups
  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListBucketMultipartUploads"
    ]
    resources = ["arn:aws:s3:::nvisionx*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts"
    ]
    resources = ["arn:aws:s3:::nvisionx*/*"]
  }

  # RDS backup permissions
  statement {
    effect = "Allow"
    actions = [
      "rds:DescribeDBSnapshots",
      "rds:CreateDBSnapshot",
      "rds:DeleteDBSnapshot",
      "rds:ModifyDBSnapshotAttribute",
      "rds:DescribeDBInstances",
      "rds:CopyDBSnapshot"
    ]
    resources = [
      "arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}:db:${var.db_identifier}",
      "arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}:snapshot:*"
    ]
  }

  # KMS permissions for encrypted backups (if needed)
  statement {
    effect = "Allow"
    actions = [
      "kms:CreateGrant",
      "kms:DescribeKey",
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey"
    ]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "kms:ViaService"
      values = [
        "rds.${var.region}.amazonaws.com",
        "s3.${var.region}.amazonaws.com"
      ]
    }
  }
}

# IAM role for Postgres backup without IRSA (basic RDS role)
resource "aws_iam_role" "postgres_backup" {
  count              = var.enable_irsa && var.enable_postgres ? 1 : 0
  name               = "${var.db_identifier}-backup-role"
  assume_role_policy = data.aws_iam_policy_document.postgres_backup_trust[0].json
  tags               = var.tags
}

# Attach inline policy to role
resource "aws_iam_role_policy" "postgres_backup" {
  count  = var.enable_irsa && var.enable_postgres ? 1 : 0
  role   = aws_iam_role.postgres_backup[0].id
  policy = data.aws_iam_policy_document.postgres_backup_policy[0].json
}
