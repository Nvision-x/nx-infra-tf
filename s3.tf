resource "random_id" "s3_suffix" {
  for_each    = toset(["logs", "minio", "companylogo", "csvfiles", "applogo", "os-backup", "postgres-backup", "cloudtrail-logs"])
  byte_length = 4
}

resource "aws_s3_bucket" "nvisionx_buckets" {
  for_each      = random_id.s3_suffix
  bucket        = "nvisionx-${each.key}-${each.value.hex}"
  force_destroy = var.s3_force_destroy

  tags = {
    Name    = "nvisionx-${each.key}"
    Purpose = "Bucket for ${each.key}"
    Project = "NvisionX"
  }
}

resource "aws_s3_bucket_versioning" "nvisionx_buckets" {
  for_each = aws_s3_bucket.nvisionx_buckets

  bucket = each.value.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "nvisionx_buckets" {
  for_each = aws_s3_bucket.nvisionx_buckets

  bucket = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "nvisionx_buckets" {
  for_each = aws_s3_bucket.nvisionx_buckets

  bucket = each.value.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "nvisionx_buckets" {
  for_each = aws_s3_bucket.nvisionx_buckets

  bucket = each.value.id

  rule {
    id     = "expire-old-objects"
    status = "Enabled"

    filter {}

    expiration {
      days = 180
    }
  }
}

# S3.5 - Require SSL/TLS for all requests (excludes cloudtrail-logs when security hub controls enabled)
resource "aws_s3_bucket_policy" "require_ssl" {
  for_each = var.enable_security_hub_controls ? { for k, v in aws_s3_bucket.nvisionx_buckets : k => v if k != "cloudtrail-logs" } : aws_s3_bucket.nvisionx_buckets

  bucket = each.value.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonSSLRequests"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          each.value.arn,
          "${each.value.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

################################################################################
# Security Hub Controls - Enabled when var.enable_security_hub_controls = true
# Controls: S3.22, S3.23, CloudTrail.2, CloudTrail.4, CloudTrail.7
################################################################################

# S3.5, S3.22 & S3.23 - CloudTrail bucket policy (SSL + CloudTrail access)
resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  count  = var.enable_security_hub_controls ? 1 : 0
  bucket = aws_s3_bucket.nvisionx_buckets["cloudtrail-logs"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonSSLRequests"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.nvisionx_buckets["cloudtrail-logs"].arn,
          "${aws_s3_bucket.nvisionx_buckets["cloudtrail-logs"].arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.nvisionx_buckets["cloudtrail-logs"].arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.nvisionx_buckets["cloudtrail-logs"].arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# CloudTrail.2 - KMS key for CloudTrail encryption (required for Security Hub compliance)
resource "aws_kms_key" "cloudtrail" {
  count                   = var.enable_security_hub_controls ? 1 : 0
  description             = "KMS key for CloudTrail log encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowCloudTrailEncrypt"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = [
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "kms:EncryptionContext:aws:cloudtrail:arn" = "arn:aws:cloudtrail:*:${data.aws_caller_identity.current.account_id}:trail/*"
          }
        }
      }
    ]
  })

  tags = {
    Name    = "nvisionx-cloudtrail-kms"
    Project = "NvisionX"
  }
}

resource "aws_kms_alias" "cloudtrail" {
  count         = var.enable_security_hub_controls ? 1 : 0
  name          = "alias/nvisionx-cloudtrail"
  target_key_id = aws_kms_key.cloudtrail[0].key_id
}

# CloudTrail.7 - S3 access logging bucket for CloudTrail bucket
resource "aws_s3_bucket" "cloudtrail_access_logs" {
  count         = var.enable_security_hub_controls ? 1 : 0
  bucket        = "nvisionx-cloudtrail-access-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.s3_force_destroy

  tags = {
    Name    = "nvisionx-cloudtrail-access-logs"
    Purpose = "Access logs for CloudTrail S3 bucket"
    Project = "NvisionX"
  }
}

resource "aws_s3_bucket_versioning" "cloudtrail_access_logs" {
  count  = var.enable_security_hub_controls ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_access_logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_access_logs" {
  count  = var.enable_security_hub_controls ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_access_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail_access_logs" {
  count  = var.enable_security_hub_controls ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_access_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "cloudtrail_access_logs" {
  count  = var.enable_security_hub_controls ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_access_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonSSLRequests"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.cloudtrail_access_logs[0].arn,
          "${aws_s3_bucket.cloudtrail_access_logs[0].arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid    = "S3ServerAccessLogsPolicy"
        Effect = "Allow"
        Principal = {
          Service = "logging.s3.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_access_logs[0].arn}/*"
        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.nvisionx_buckets["cloudtrail-logs"].arn
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail_access_logs" {
  count  = var.enable_security_hub_controls ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_access_logs[0].id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = 90
    }
  }
}

# CloudTrail.7 - Enable access logging on CloudTrail bucket
resource "aws_s3_bucket_logging" "cloudtrail_logs" {
  count  = var.enable_security_hub_controls ? 1 : 0
  bucket = aws_s3_bucket.nvisionx_buckets["cloudtrail-logs"].id

  target_bucket = aws_s3_bucket.cloudtrail_access_logs[0].id
  target_prefix = "access-logs/"
}

# S3.22, S3.23, CloudTrail.4 - CloudTrail for S3 data events
resource "aws_cloudtrail" "s3_data_events" {
  count                         = var.enable_security_hub_controls ? 1 : 0
  name                          = "nvisionx-s3-data-events"
  s3_bucket_name                = aws_s3_bucket.nvisionx_buckets["cloudtrail-logs"].id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_logging                = true
  enable_log_file_validation    = true                          # CloudTrail.4
  kms_key_id                    = aws_kms_key.cloudtrail[0].arn # CloudTrail.2

  event_selector {
    read_write_type           = "All"
    include_management_events = false

    data_resource {
      type = "AWS::S3::Object"
      # When cloudtrail_log_all_s3_buckets=true: logs ALL buckets (required for S3.22/S3.23 compliance)
      # When cloudtrail_log_all_s3_buckets=false: logs only NvisionX managed buckets (for customer deployments)
      values = var.cloudtrail_log_all_s3_buckets ? ["arn:aws:s3:::"] : [for k, v in aws_s3_bucket.nvisionx_buckets : "${v.arn}/*" if k != "cloudtrail-logs"]
    }
  }

  tags = {
    Name    = "nvisionx-s3-data-events"
    Purpose = "S3 object-level logging for Security Hub compliance"
    Project = "NvisionX"
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail_logs]
}
