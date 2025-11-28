resource "random_id" "s3_suffix" {
  for_each    = toset(["logs", "minio", "companylogo", "csvfiles", "applogo", "os-backup", "postgres-backup"])
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

# S3.5 - Require SSL/TLS for all requests
resource "aws_s3_bucket_policy" "require_ssl" {
  for_each = aws_s3_bucket.nvisionx_buckets

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

# S3.22 & S3.23 - CloudTrail for object-level read/write events
resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket        = "nvisionx-cloudtrail-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.s3_force_destroy

  tags = {
    Name    = "nvisionx-cloudtrail-logs"
    Purpose = "CloudTrail S3 data event logs"
    Project = "NvisionX"
  }
}

resource "aws_s3_bucket_versioning" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonSSLRequests"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.cloudtrail_logs.arn,
          "${aws_s3_bucket.cloudtrail_logs.arn}/*"
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
        Resource = aws_s3_bucket.cloudtrail_logs.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_logs.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

resource "aws_cloudtrail" "s3_data_events" {
  name                          = "nvisionx-s3-data-events"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.id
  include_global_service_events = false
  is_multi_region_trail         = true
  enable_logging                = true

  event_selector {
    read_write_type           = "All"
    include_management_events = false

    data_resource {
      type   = "AWS::S3::Object"
      values = [for bucket in aws_s3_bucket.nvisionx_buckets : "${bucket.arn}/"]
    }
  }

  tags = {
    Name    = "nvisionx-s3-data-events"
    Purpose = "S3 object-level logging for Security Hub compliance"
    Project = "NvisionX"
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail_logs]
}
