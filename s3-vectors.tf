# S3 Vectors bucket — native vector storage for embeddings/RAG workloads.
# Indexes are intentionally not created here: dimension and distance metric
# are per-use-case decisions that belong with the application that owns them.

resource "aws_s3vectors_vector_bucket" "this" {
  count              = var.enable_s3_vectors ? 1 : 0
  vector_bucket_name = var.s3_vectors_bucket_name

  encryption_configuration {
    sse_type = "AES256"
  }

  tags = var.tags
}
