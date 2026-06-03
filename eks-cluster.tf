resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.cluster_version

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnets

  endpoint_private_access                  = var.cluster_endpoint_private_access
  endpoint_public_access                   = var.cluster_endpoint_public_access
  endpoint_public_access_cidrs             = var.cluster_endpoint_public_access_cidrs
  enable_irsa                              = false # Using Pod Identity instead
  create_iam_role                          = var.create_iam_role
  iam_role_arn                             = var.cluster_iam_role_arn
  eks_managed_node_groups                  = var.eks_managed_node_groups
  enable_cluster_creator_admin_permissions = true

  addons = merge(
    {
      coredns = merge(
        { before_compute = true },
        var.coredns_configuration_values != null ? { configuration_values = var.coredns_configuration_values } : {}
      )
      eks-pod-identity-agent = { before_compute = true }
      kube-proxy             = { before_compute = true }
      vpc-cni                = { before_compute = true }
      aws-ebs-csi-driver = {
        # Use Pod Identity instead of IRSA for EBS CSI
        # This replaces the old service_account_role_arn approach
        pod_identity_association = [{
          role_arn        = var.ebs_csi_role_arn
          service_account = "ebs-csi-controller-sa"
        }]
      }
    },
    var.enable_efs ? {
      aws-efs-csi-driver = {
        pod_identity_association = [{
          role_arn        = var.efs_csi_role_arn
          service_account = "efs-csi-controller-sa"
        }]
      }
    } : {},
    {
      # Disable Application Signals auto-monitoring to prevent OTEL injection
      # This stops auto-instrumentation of all languages (Java, Python, Node, .NET)
      # CloudWatch Container Insights and logs still work
      amazon-cloudwatch-observability = {
        configuration_values = jsonencode({
          manager = {
            applicationSignals = {
              autoMonitor = {
                monitorAllServices = false
              }
            }
          }
        })
      }
    }
  )

  tags = var.tags
}

resource "aws_security_group_rule" "eks_control_plane_ingress" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = module.eks.cluster_security_group_id # EKS control plane security group
  cidr_blocks       = [var.vpc_cidr_block]
  description       = "Allow API (443) from VPC"
}

# Allow all traffic within VPC for pod-to-pod & node-to-node communication
resource "aws_security_group_rule" "eks_nodes_all_vpc_ingress" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1"
  security_group_id = module.eks.node_security_group_id
  cidr_blocks       = [var.vpc_cidr_block]
  description       = "Allow all traffic from within VPC for node-to-node/pod-to-pod communication"
}

# This resource was migrated from `count` (single principal, address `[0]`) to
# `for_each` (map keyed by name). Without the moved blocks below, Terraform reads
# the address change `[0]` -> `["admin"]` as destroy+recreate, which deletes the
# admin EKS access entry mid-apply and locks operators out of the cluster. The
# moved blocks carry the existing object to the new key instead. They assume the
# previously-single principal is passed under the map key "admin" (the convention
# in the root configs); an env that used a different key must adjust accordingly.
# Already-migrated states have nothing at `[0]`, so the moved block is a safe no-op.
moved {
  from = aws_eks_access_entry.access[0]
  to   = aws_eks_access_entry.access["admin"]
}

moved {
  from = aws_eks_access_policy_association.access_policy[0]
  to   = aws_eks_access_policy_association.access_policy["admin"]
}

resource "aws_eks_access_entry" "access" {
  for_each      = var.eks_access_principal_arn
  cluster_name  = module.eks.cluster_name
  principal_arn = each.value
  type          = "STANDARD"

  # Guardrail: refuse to destroy an admin access entry. A future address change
  # or an accidental removal will then fail the plan loudly instead of silently
  # revoking cluster access (the failure mode that originally locked us out). To
  # intentionally revoke a principal, remove it from the map AND drop this block
  # in the same change.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_eks_access_policy_association" "access_policy" {
  for_each      = var.eks_access_principal_arn
  cluster_name  = module.eks.cluster_name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = each.value

  access_scope {
    type = "cluster"
  }
}

locals {
  pg_host     = var.enable_postgres ? module.postgresql[0].db_instance_address : null
  pg_username = var.enable_postgres ? var.username : null

  os_host     = var.enable_opensearch ? module.opensearch[0].domain_endpoint : null
  os_username = var.enable_opensearch ? var.master_user_name : null

  neptune_host = var.enable_neptune ? aws_neptune_cluster.this[0].endpoint : null
  neptune_port = var.enable_neptune ? tostring(aws_neptune_cluster.this[0].port) : null

  s3_vectors_bucket = var.enable_s3_vectors ? aws_s3vectors_vector_bucket.this[0].vector_bucket_name : null
}


resource "kubernetes_config_map" "infra_config" {
  metadata {
    name      = "infra-config"
    namespace = "default"
  }

  data = merge(
    {
      S3_BUCKET                     = aws_s3_bucket.nvisionx_buckets["logs"].bucket
      MINIO_BUCKET                  = aws_s3_bucket.nvisionx_buckets["minio"].bucket
      MINIO_LOGO_BUCKET             = aws_s3_bucket.nvisionx_buckets["companylogo"].bucket
      MINIO_CSV_BUCKET              = aws_s3_bucket.nvisionx_buckets["csvfiles"].bucket
      MINIO_APPLICATION_LOGO_BUCKET = aws_s3_bucket.nvisionx_buckets["applogo"].bucket
      S3_DOWNLOAD_BUCKET            = aws_s3_bucket.nvisionx_buckets["downloads"].bucket
      S3_POSTGRES_BACKUP_BUCKET     = aws_s3_bucket.nvisionx_buckets["postgres-backup"].bucket
      S3_OPENSEARCH_BACKUP_BUCKET   = aws_s3_bucket.nvisionx_buckets["os-backup"].bucket
      S3_RAW_CONTENT_CACHE_BUCKET   = aws_s3_bucket.nvisionx_buckets["raw-content-cache"].bucket
      S3_TEXT_CONTENT_CACHE_BUCKET  = aws_s3_bucket.nvisionx_buckets["text-content-cache"].bucket
      APPCUES_ACCOUNT_ID            = var.appcues_account_id
      APPCUES_BUNDLE_DOMAIN         = var.appcues_bundle_domain
      APPCUES_API_HOSTNAME          = var.appcues_api_hostname
    },

    // Add PG, OS, Neptune, S3 Vectors only when enabled
    { for k, v in {
      POSTGRES_HOST       = local.pg_host
      POSTGRES_USERNAME   = local.pg_username
      OPENSEARCH_HOST     = local.os_host
      OPENSEARCH_USERNAME = local.os_username
      NEPTUNE_HOST        = local.neptune_host
      NEPTUNE_PORT        = local.neptune_port
      S3_VECTORS_BUCKET   = local.s3_vectors_bucket
    } : k => v if v != null },

    var.ingress_internet_facing != null ? { ingress-internet-facing = var.ingress_internet_facing } : {},
    var.ingress_certificate_arn != null ? { ingress-certificate-arn = var.ingress_certificate_arn } : {},
    var.ingress_wafv2_acl_arn != null ? { ingress-wafv2-acl-arn = var.ingress_wafv2_acl_arn } : {},
    var.ingress_host != null ? { ingress-host = var.ingress_host } : {},
    { snapshot-repository-name = var.snapshot_repository_name },
    # aws-region kept for backward compat; AWS_REGION added so envFrom works
    # (envFrom silently skips keys that aren't valid env var names, e.g. hyphenated)
    { aws-region = var.region },
    { AWS_REGION = var.region }
  )
}


resource "kubernetes_secret" "infra_secrets" {
  count = var.enable_postgres && var.enable_opensearch ? 1 : 0

  metadata {
    name      = "infra-secrets"
    namespace = "default"
  }
  data = {
    POSTGRES_PASSWORD   = jsondecode(data.aws_secretsmanager_secret_version.postgres[0].secret_string).password
    OPENSEARCH_PASSWORD = jsondecode(data.aws_secretsmanager_secret_version.opensearch[0].secret_string).password
  }
  type = "Opaque"
}

locals {
  docker_auth_b64    = base64encode("${trimspace(var.docker_hub_username)}:${trimspace(var.docker_hub_token)}")
  github_cr_auth_b64 = base64encode("${trimspace(var.github_cr_username)}:${trimspace(var.github_cr_token)}")

  # PLAIN JSON (not base64)
  dockerconfigjson = jsonencode({
    auths = {
      "https://index.docker.io/v1/" = {
        auth     = local.docker_auth_b64
        username = trimspace(var.docker_hub_username) # optional
        password = trimspace(var.docker_hub_token)    # optional
      }
    }
  })

  # PLAIN JSON for GitHub Container Registry (not base64)
  githubcrconfigjson = jsonencode({
    auths = {
      "ghcr.io" = {
        auth     = local.github_cr_auth_b64
        username = trimspace(var.github_cr_username) # optional
        password = trimspace(var.github_cr_token)    # optional
      }
    }
  })
}

resource "kubernetes_secret" "docker_hub" {
  count = length(trimspace(var.docker_hub_username)) > 0 && length(trimspace(var.docker_hub_token)) > 0 ? 1 : 0

  metadata {
    name      = "docker-hub-secret"
    namespace = "default"
  }

  type = "kubernetes.io/dockerconfigjson"

  # DO NOT base64 here; provider will do it.
  data = {
    ".dockerconfigjson" = local.dockerconfigjson
  }
}

resource "kubernetes_secret" "github_cr" {
  count = length(trimspace(var.github_cr_username)) > 0 && length(trimspace(var.github_cr_token)) > 0 ? 1 : 0

  metadata {
    name      = "github-cr-secret"
    namespace = "default"
  }

  type = "kubernetes.io/dockerconfigjson"

  # DO NOT base64 here; provider will do it.
  data = {
    ".dockerconfigjson" = local.githubcrconfigjson
  }
}

# Requires terraform-provider-kubernetes >= 2.x
resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type   = "gp3"
    fsType = "ext4"
  }
}






