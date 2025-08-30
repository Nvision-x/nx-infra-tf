# IAM role for OpenSearch snapshots
resource "aws_iam_role" "opensearch_snapshot" {
  count = var.enable_opensearch ? 1 : 0
  name  = "${var.domain_name}-snapshot-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "es.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

# IAM policy for OpenSearch to access S3 bucket
resource "aws_iam_policy" "opensearch_snapshot" {
  count = var.enable_opensearch ? 1 : 0
  name  = "${var.domain_name}-snapshot-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.nvisionx_buckets["nvisionx-os-backup"].arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.nvisionx_buckets["nvisionx-os-backup"].arn}/*"
      }
    ]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "opensearch_snapshot" {
  count      = var.enable_opensearch ? 1 : 0
  role       = aws_iam_role.opensearch_snapshot[0].name
  policy_arn = aws_iam_policy.opensearch_snapshot[0].arn
}

# Pass role to OpenSearch domain
resource "aws_iam_service_linked_role" "opensearch" {
  count            = var.enable_opensearch ? 1 : 0
  aws_service_name = "es.amazonaws.com"
}

# Output for snapshot repository registration
output "opensearch_snapshot_role_arn" {
  description = "ARN of the IAM role for OpenSearch snapshots"
  value       = var.enable_opensearch ? aws_iam_role.opensearch_snapshot[0].arn : null
}

output "opensearch_snapshot_bucket" {
  description = "S3 bucket name for OpenSearch snapshots"
  value       = aws_s3_bucket.nvisionx_buckets["nvisionx-os-backup"].id
}

# Register snapshot repository via bastion host
resource "null_resource" "register_snapshot_repository" {
  count = var.enable_opensearch && var.enable_bastion ? 1 : 0
  
  depends_on = [
    module.opensearch[0],
    aws_iam_role.opensearch_snapshot[0],
    aws_iam_role_policy_attachment.opensearch_snapshot[0],
    aws_instance.bastion_ec2[0]
  ]

  triggers = {
    opensearch_endpoint = module.opensearch[0].domain_endpoint
    snapshot_role_arn   = aws_iam_role.opensearch_snapshot[0].arn
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = var.bastion_existing_pem != "" ? file(var.bastion_existing_pem) : tls_private_key.bastion_ec2_key[0].private_key_pem
    host        = aws_instance.bastion_ec2[0].public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Creating snapshot registration script...'",
      "cat > /tmp/register_snapshot.sh << 'SCRIPT_EOF'",
      "#!/bin/bash",
      "set -e",
      "echo 'Waiting for OpenSearch domain to be fully active...'",
      "sleep 120",
      "",
      "OS_ENDPOINT='${module.opensearch[0].domain_endpoint}'",
      "OS_USER='${var.master_user_name}'",
      "OS_PASS='${jsondecode(data.aws_secretsmanager_secret_version.opensearch[0].secret_string).password}'",
      "S3_BUCKET='${aws_s3_bucket.nvisionx_buckets["nvisionx-os-backup"].id}'",
      "ROLE_ARN='${aws_iam_role.opensearch_snapshot[0].arn}'",
      "REGION='${var.region}'",
      "",
      "echo '==================================='",
      "echo 'Snapshot Repository Configuration:'",
      "echo '==================================='",
      "echo \"Endpoint: $OS_ENDPOINT\"",
      "echo \"Bucket: $S3_BUCKET\"",
      "echo \"Role ARN: $ROLE_ARN\"",
      "echo \"Region: $REGION\"",
      "echo \"User: $OS_USER\"",
      "echo '==================================='",
      "",
      "echo 'Registering snapshot repository...'",
      "RESPONSE=$(curl -s -w '\\nHTTP_STATUS:%%{http_code}' -X PUT \"https://$OS_ENDPOINT/_snapshot/s3_repository\" \\",
      "  -u \"$OS_USER:$OS_PASS\" \\",
      "  -H 'Content-Type: application/json' \\",
      "  -d \"{",
      "    \\\"type\\\": \\\"s3\\\",",
      "    \\\"settings\\\": {",
      "      \\\"bucket\\\": \\\"$S3_BUCKET\\\",",
      "      \\\"region\\\": \\\"$REGION\\\",",
      "      \\\"role_arn\\\": \\\"$ROLE_ARN\\\"",
      "    }",
      "  }\" -k 2>&1)",
      "",
      "HTTP_STATUS=$(echo \"$RESPONSE\" | grep 'HTTP_STATUS:' | cut -d: -f2)",
      "BODY=$(echo \"$RESPONSE\" | sed '/HTTP_STATUS:/d')",
      "",
      "echo 'Registration Response:'",
      "echo \"$BODY\" | python3 -m json.tool 2>/dev/null || echo \"$BODY\"",
      "echo \"HTTP Status: $HTTP_STATUS\"",
      "",
      "if [ \"$HTTP_STATUS\" != \"200\" ] && [ \"$HTTP_STATUS\" != \"201\" ]; then",
      "  echo 'ERROR: Failed to register snapshot repository!'",
      "  echo 'Common issues:'",
      "  echo '1. IAM role trust relationship not configured for OpenSearch'",
      "  echo '2. IAM role missing S3 permissions'",
      "  echo '3. OpenSearch domain not configured to pass IAM role'",
      "  exit 1",
      "fi",
      "",
      "echo 'Verifying repository...'",
      "sleep 5",
      "",
      "VERIFY=$(curl -s -X GET \"https://$OS_ENDPOINT/_snapshot/s3_repository\" \\",
      "  -u \"$OS_USER:$OS_PASS\" -k)",
      "",
      "echo 'Verification Result:'",
      "echo \"$VERIFY\" | python3 -m json.tool 2>/dev/null || echo \"$VERIFY\"",
      "",
      "echo 'SUCCESS: Snapshot repository registered!'",
      "SCRIPT_EOF",
      "",
      "chmod +x /tmp/register_snapshot.sh",
      "echo 'Executing registration script...'",
      "/tmp/register_snapshot.sh",
      "rm -f /tmp/register_snapshot.sh"
    ]
  }
}

# Output snapshot repository commands for manual execution
output "opensearch_snapshot_commands" {
  description = "Commands to manage OpenSearch snapshots (run from bastion host)"
  value = var.enable_opensearch ? (<<-EOT
    # SSH to bastion host:
    ssh -i ${var.bastion_existing_pem != "" ? var.bastion_existing_pem : "<RETRIEVE_PRIVATE_KEY_FROM_SECRETS_MANAGER>"} ubuntu@${var.enable_bastion ? aws_instance.bastion_ec2[0].public_ip : "<BASTION_IP>"}
    
    # Create a snapshot:
    curl -X PUT "https://${module.opensearch[0].domain_endpoint}/_snapshot/s3_repository/snapshot_$(date +%Y%m%d_%H%M%S)?wait_for_completion=false" \
      -u "${var.master_user_name}:<PASSWORD>" -k
    
    # List all snapshots:
    curl -X GET "https://${module.opensearch[0].domain_endpoint}/_snapshot/s3_repository/_all" \
      -u "${var.master_user_name}:<PASSWORD>" -k
    
    # Restore a snapshot:
    curl -X POST "https://${module.opensearch[0].domain_endpoint}/_snapshot/s3_repository/<SNAPSHOT_NAME>/_restore" \
      -u "${var.master_user_name}:<PASSWORD>" -k
EOT
  ) : null
}