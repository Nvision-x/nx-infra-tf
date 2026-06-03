# Kubernetes ServiceAccount for the knowledge-hub workload.
# The Pod Identity association in pod-identity-associations.tf references this
# SA by name; without the SA actually existing in the cluster, pods that set
# spec.serviceAccountName: knowledge-hub are rejected with
#   "error looking up service account default/knowledge-hub: ... not found"
# Mirrors the kubernetes_service_account.bedrock pattern.

locals {
  knowledge_hub_sa_create = var.enable_knowledge_hub_pod_identity && var.create_knowledge_hub_service_account && var.knowledge_hub_service_account != ""
  knowledge_hub_sa_ns     = local.knowledge_hub_sa_create ? split(":", var.knowledge_hub_service_account)[0] : ""
  knowledge_hub_sa_name   = local.knowledge_hub_sa_create ? split(":", var.knowledge_hub_service_account)[1] : ""
}

resource "kubernetes_service_account" "knowledge_hub" {
  count = local.knowledge_hub_sa_create ? 1 : 0

  metadata {
    name      = local.knowledge_hub_sa_name
    namespace = local.knowledge_hub_sa_ns

    labels = {
      "app.kubernetes.io/name"       = local.knowledge_hub_sa_name
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "knowledge-hub"
    }
  }

  automount_service_account_token = true

  lifecycle {
    # Helm/app may add its own labels/annotations; don't fight them.
    ignore_changes = [metadata[0].labels, metadata[0].annotations]
  }
}
