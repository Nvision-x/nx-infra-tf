################################################################################
# Amazon Bedrock - Kubernetes Service Accounts
################################################################################

# Parse the service account strings (format: "namespace:serviceaccount")
locals {
  bedrock_service_accounts_parsed = var.enable_bedrock_service_accounts ? {
    for sa in var.bedrock_service_accounts : sa => {
      namespace = split(":", sa)[0]
      name      = split(":", sa)[1]
    }
  } : {}
}

# Create namespaces for Bedrock service accounts if they don't exist
resource "kubernetes_namespace" "bedrock" {
  for_each = var.enable_bedrock_service_accounts && var.create_bedrock_namespaces ? toset([
    for sa in var.bedrock_service_accounts : split(":", sa)[0]
  ]) : toset([])

  metadata {
    name = each.value
    labels = {
      name                = each.value
      "managed-by"        = "terraform"
      "bedrock-access"    = "enabled"
      "app.kubernetes.io" = "bedrock-app"
    }
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations,
      metadata[0].labels,
    ]
  }
}

# Create Kubernetes ServiceAccounts with IRSA annotation
resource "kubernetes_service_account" "bedrock" {
  for_each = local.bedrock_service_accounts_parsed

  metadata {
    name      = local.bedrock_service_accounts_parsed[each.key].name
    namespace = local.bedrock_service_accounts_parsed[each.key].namespace

    annotations = {
      "eks.amazonaws.com/role-arn"               = var.bedrock_irsa_role_arn
      "eks.amazonaws.com/sts-regional-endpoints" = "true"
    }

    labels = {
      "app.kubernetes.io/name"       = local.bedrock_service_accounts_parsed[each.key].name
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "bedrock-access"
      "bedrock-enabled"              = "true"
    }
  }

  # Automatically mount service account token
  automount_service_account_token = true

  depends_on = [
    kubernetes_namespace.bedrock
  ]
}
