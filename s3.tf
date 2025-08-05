resource "random_id" "s3_suffix" {
  for_each    = toset(["logs", "minio", "companylogo", "csvfiles", "applogo"])
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
