################################################################################
# Pod Identity Associations
# Created after EKS cluster exists - links IAM roles to Kubernetes service accounts
# IAM roles are created in nx-iam-tf (no EKS dependency)
#
# Note: count/for_each conditions use plan-time known variables (not role ARNs)
# because role ARNs come from another module and aren't known until apply.
################################################################################

################################################################################
# EBS CSI Driver Pod Identity Association
################################################################################

resource "aws_eks_pod_identity_association" "ebs_csi" {
  # EBS CSI is always enabled for EKS clusters
  count = 1

  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = var.ebs_csi_role_arn

  depends_on = [module.eks]
}

################################################################################
# Cluster Autoscaler Pod Identity Association
################################################################################

resource "aws_eks_pod_identity_association" "cluster_autoscaler" {
  # Use service account name (plan-time known) instead of role ARN
  count = var.autoscaler_service_account != "" ? 1 : 0

  cluster_name    = module.eks.cluster_name
  namespace       = var.namespace
  service_account = var.autoscaler_service_account
  role_arn        = var.cluster_autoscaler_role_arn

  depends_on = [module.eks]
}

################################################################################
# Load Balancer Controller Pod Identity Association
################################################################################

resource "aws_eks_pod_identity_association" "lb_controller" {
  # Use service account name (plan-time known) instead of role ARN
  count = var.lb_controller_service_account != "" ? 1 : 0

  cluster_name    = module.eks.cluster_name
  namespace       = var.namespace
  service_account = var.lb_controller_service_account
  role_arn        = var.lb_controller_role_arn

  depends_on = [module.eks]
}

################################################################################
# Postgres Backup Pod Identity Association
################################################################################

resource "aws_eks_pod_identity_association" "postgres_backup" {
  # Use enable_postgres flag (plan-time known) instead of role ARN check
  count = var.enable_postgres ? 1 : 0

  cluster_name    = module.eks.cluster_name
  namespace       = var.postgres_backup_namespace
  service_account = var.postgres_backup_service_account
  role_arn        = var.postgres_backup_role_arn

  depends_on = [module.eks]
}

################################################################################
# Application S3 Access Pod Identity Associations
################################################################################

locals {
  # Parse app S3 service accounts - use enable flag only (plan-time known)
  app_s3_sa_pairs = var.enable_app_s3_access ? {
    for sa in var.app_s3_service_accounts : sa => {
      namespace       = split(":", sa)[0]
      service_account = split(":", sa)[1]
    }
  } : {}
}

resource "aws_eks_pod_identity_association" "app_s3" {
  for_each = local.app_s3_sa_pairs

  cluster_name    = module.eks.cluster_name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = var.app_s3_role_arn

  depends_on = [module.eks]
}

################################################################################
# Bedrock Pod Identity Associations
################################################################################

locals {
  # Parse Bedrock service accounts - use enable flag only (plan-time known)
  bedrock_sa_pairs = var.enable_bedrock_irsa ? {
    for sa in var.bedrock_service_accounts : sa => {
      namespace       = split(":", sa)[0]
      service_account = split(":", sa)[1]
    }
  } : {}
}

resource "aws_eks_pod_identity_association" "bedrock" {
  for_each = local.bedrock_sa_pairs

  cluster_name    = module.eks.cluster_name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = var.bedrock_role_arn

  depends_on = [module.eks]
}
