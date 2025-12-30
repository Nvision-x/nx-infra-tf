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

output "eks_oidc_provider_arn" {
  description = "The OIDC provider ARN for the EKS cluster"
  value       = module.eks.oidc_provider_arn
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

output "oidc_provider_url" {
  description = "The OpenID Connect identity provider (issuer URL)"
  value       = try("https://${module.eks.oidc_provider}", null)
}

output "bedrock_service_accounts" {
  description = "List of created Kubernetes ServiceAccounts for Bedrock access"
  value = var.enable_bedrock_service_accounts ? {
    for k, v in kubernetes_service_account.bedrock : k => {
      name      = v.metadata[0].name
      namespace = v.metadata[0].namespace
      role_arn  = v.metadata[0].annotations["eks.amazonaws.com/role-arn"]
    }
  } : {}
}

output "bedrock_irsa_role_arn" {
  description = "IAM Role ARN for Amazon Bedrock access from EKS pods (created in nx-infra-tf for full auto deployment)"
  value       = try(module.irsa[0].bedrock_iam_role_arn, null)
}

output "bedrock_iam_policy_arn" {
  description = "IAM Policy ARN for Amazon Bedrock access (contains capability and provider filtering)"
  value       = try(module.irsa[0].bedrock_iam_policy_arn, null)
}

output "bedrock_enabled_capabilities" {
  description = "List of enabled Bedrock capabilities"
  value       = var.enable_bedrock_irsa ? var.bedrock_capabilities : []
}

output "bedrock_enabled_providers" {
  description = "List of enabled Bedrock model providers (after filtering)"
  value       = try(module.irsa[0].bedrock_enabled_providers, [])
}

output "postgres_backup_role_arn" {
  description = "ARN of the IAM role for Postgres backup (created in infra module when IRSA is enabled)"
  value       = try(module.irsa[0].postgres_backup_iam_role_arn, null)
}

output "lb_controller_irsa_role_arn" {
  description = "IAM Role ARN for AWS Load Balancer Controller"
  value       = try(module.irsa[0].lb_controller_iam_role_arn, null)
}

output "cluster_autoscaler_irsa_role_arn" {
  description = "IAM Role ARN for Cluster Autoscaler"
  value       = try(module.irsa[0].cluster_autoscaler_iam_role_arn, null)
}

output "ebs_csi_irsa_role_arn" {
  description = "EBS CSI IRSA role ARN"
  value       = try(module.irsa[0].ebs_csi_iam_role_arn, null)
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