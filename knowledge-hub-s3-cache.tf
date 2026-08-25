# knowledge-hub reads the text cache that content-service writes; it never
# writes there, so GetObject only.
#
# Here and not in nx-iam-tf: only this module knows the bucket ARN, and
# nx-iam-tf can't depend on it (nx-infra-tf already consumes the role ARN).
# Same attach-to-passed-in-role pattern as aws_iam_policy.neptune_connect.

resource "aws_iam_policy" "knowledge_hub_text_cache_read" {
  count = var.enable_knowledge_hub_pod_identity ? 1 : 0
  name  = "${var.cluster_name}-knowledge-hub-text-cache-read"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "TextContentCacheRead"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.nvisionx_buckets["text-content-cache"].arn}/*"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "knowledge_hub_text_cache_read" {
  # count stays plan-time known; caller must pass a real ARN when the flag is on.
  count      = var.enable_knowledge_hub_pod_identity ? 1 : 0
  role       = split("/", var.knowledge_hub_role_arn)[1]
  policy_arn = aws_iam_policy.knowledge_hub_text_cache_read[0].arn
}
