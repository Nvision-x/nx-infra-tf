output "eks_cluster_endpoint" {
  description = "The endpoint for the EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_ca" {
  description = "The base64-encoded CA certificate for the EKS cluster"
  value       = module.eks.cluster_certificate_authority_data
}

output "eks_cluster_name" {
  description = "The name of the EKS cluster"
  value       = module.eks.cluster_name
}

# Output the private key for the user
output "private_key_pem" {
  description = "The private key in PEM format (only generated if enable_nfs is true and no existing PEM is provided)"
  value       = var.enable_nfs && var.existing_pem == "" ? tls_private_key.ec2_key[0].private_key_pem : null
  sensitive   = true
}

output "bastion_private_key_pem" {
  description = "The private key in PEM format (only generated if enable_bastion is true and no existing PEM is provided)"
  value       = var.enable_bastion && var.bastion_existing_pem == "" ? tls_private_key.bastion_ec2_key[0].private_key_pem : null
  sensitive   = true
}

output "eks_control_plane_ingress_rule_id" {
  value = aws_security_group_rule.eks_control_plane_ingress.id
}

output "bedrock_service_accounts" {
  description = "List of created Kubernetes ServiceAccounts for Bedrock access"
  value = var.enable_bedrock_service_accounts ? {
    for k, v in kubernetes_service_account.bedrock : k => {
      name      = v.metadata[0].name
      namespace = v.metadata[0].namespace
    }
  } : {}
}

output "bedrock_enabled_capabilities" {
  description = "List of enabled Bedrock capabilities"
  value       = var.enable_bedrock_irsa ? var.bedrock_capabilities : []
}

output "efs_file_system_id" {
  description = "EFS filesystem ID"
  value       = var.enable_efs ? aws_efs_file_system.this[0].id : null
}

# --------------------- CloudTrail (for security baseline) -----------------------------

output "cloudtrail_bucket_name" {
  description = "Name of S3 bucket for CloudTrail logs"
  value       = try(aws_s3_bucket.nvisionx_buckets["cloudtrail-logs"].id, null)
}

output "cloudtrail_access_logs_bucket_name" {
  description = "Name of S3 bucket for CloudTrail access logs"
  value       = var.enable_security_hub_controls ? aws_s3_bucket.cloudtrail_access_logs[0].id : null
}

output "cloudtrail_kms_key_arn" {
  description = "ARN of KMS key for CloudTrail encryption"
  value       = var.enable_security_hub_controls ? aws_kms_key.cloudtrail[0].arn : null
}

# --------------------- Neptune Serverless -----------------------------

output "neptune_cluster_endpoint" {
  description = "Neptune cluster writer endpoint"
  value       = var.enable_neptune ? aws_neptune_cluster.this[0].endpoint : null
}

output "neptune_cluster_reader_endpoint" {
  description = "Neptune cluster reader endpoint"
  value       = var.enable_neptune ? aws_neptune_cluster.this[0].reader_endpoint : null
}

output "neptune_cluster_port" {
  description = "Neptune cluster port"
  value       = var.enable_neptune ? aws_neptune_cluster.this[0].port : null
}

output "neptune_cluster_resource_id" {
  description = "Neptune cluster resource ID — used for IAM neptune-db:* resource ARNs"
  value       = var.enable_neptune ? aws_neptune_cluster.this[0].cluster_resource_id : null
}

output "neptune_cluster_arn" {
  description = "Neptune cluster ARN"
  value       = var.enable_neptune ? aws_neptune_cluster.this[0].arn : null
}

# --------------------- S3 Vectors -------------------------------------

output "s3_vectors_bucket_name" {
  description = "S3 Vectors vector bucket name"
  value       = var.enable_s3_vectors ? aws_s3vectors_vector_bucket.this[0].vector_bucket_name : null
}

output "s3_vectors_bucket_arn" {
  description = "S3 Vectors vector bucket ARN"
  value       = var.enable_s3_vectors ? aws_s3vectors_vector_bucket.this[0].arn : null
}
