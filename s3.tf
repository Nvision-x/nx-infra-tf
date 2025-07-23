# S3 Bucket for NvisionX production logs
resource "aws_s3_bucket" "nvisionx_logs" {
  bucket        = "nvisionx-logs-prod-${data.aws_caller_identity.current.account_id}"
  force_destroy = false

  tags = {
    Name        = "NvisionXLogsBucket"
    Environment = "nvisionx-prod"
    Purpose     = "Store NvisionX logs from Fluentd"
  }
}

# Enable versioning (recommended for log retention/audit)
resource "aws_s3_bucket_versioning" "nvisionx_logs" {
  bucket = aws_s3_bucket.nvisionx_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "nvisionx_logs" {
  bucket = aws_s3_bucket.nvisionx_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "nvisionx_logs" {
  bucket = aws_s3_bucket.nvisionx_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy - delete logs after 180 days (adjust as needed)
resource "aws_s3_bucket_lifecycle_configuration" "nvisionx_logs" {
  bucket = aws_s3_bucket.nvisionx_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {} # <- This makes it valid for all objects

    expiration {
      days = 180
    }
  }
}

