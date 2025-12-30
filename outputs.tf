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

# --------------------- CloudTrail (for security baseline) -----------------------------

output "cloudtrail_bucket_name" {
  description = "Name of S3 bucket for CloudTrail logs"
  value       = var.enable_security_hub_controls ? aws_s3_bucket.nvisionx_buckets["cloudtrail-logs"].id : null
}

output "cloudtrail_access_logs_bucket_name" {
  description = "Name of S3 bucket for CloudTrail access logs"
  value       = var.enable_security_hub_controls ? aws_s3_bucket.cloudtrail_access_logs[0].id : null
}

output "cloudtrail_kms_key_arn" {
  description = "ARN of KMS key for CloudTrail encryption"
  value       = var.enable_security_hub_controls ? aws_kms_key.cloudtrail[0].arn : null
}
