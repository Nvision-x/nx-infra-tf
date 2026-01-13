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

  endpoint_private_access      = var.cluster_endpoint_private_access
  endpoint_public_access       = var.cluster_endpoint_public_access
  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  enable_irsa                  = false # Using Pod Identity instead
  create_iam_role              = var.create_iam_role
  iam_role_arn                 = var.cluster_iam_role_arn
  eks_managed_node_groups      = var.eks_managed_node_groups
  enable_cluster_creator_admin_permissions = true

  addons = {
    coredns                = {}
    eks-pod-identity-agent = {}
    kube-proxy             = {}
    vpc-cni                = {}
    aws-ebs-csi-driver = {
      # Use Pod Identity instead of IRSA for EBS CSI
      # This replaces the old service_account_role_arn approach
      pod_identity_association = [{
        role_arn        = var.ebs_csi_role_arn
        service_account = "ebs-csi-controller-sa"
      }]
    }
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

resource "aws_eks_access_entry" "access" {
  count         = var.eks_access_principal_arn != null ? 1 : 0
  cluster_name  = module.eks.cluster_name
  principal_arn = var.eks_access_principal_arn
  type          = "STANDARD"

  tags = {
    Name = "admin-access"
  }
}

resource "aws_eks_access_policy_association" "access_policy" {
  count         = var.eks_access_principal_arn != null ? 1 : 0
  cluster_name  = module.eks.cluster_name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = var.eks_access_principal_arn

  access_scope {
    type = "cluster"
  }
}

locals {
  pg_host     = var.enable_postgres ? module.postgresql[0].db_instance_address : null
  pg_username = var.enable_postgres ? var.username : null

  os_host     = var.enable_opensearch ? module.opensearch[0].domain_endpoint : null
  os_username = var.enable_opensearch ? var.master_user_name : null
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
    },

    // Add PG & OS only when enabled
    { for k, v in {
      POSTGRES_HOST       = local.pg_host
      POSTGRES_USERNAME   = local.pg_username
      OPENSEARCH_HOST     = local.os_host
      OPENSEARCH_USERNAME = local.os_username
    } : k => v if v != null },

    var.ingress_internet_facing != null ? { ingress-internet-facing = var.ingress_internet_facing } : {},
    var.ingress_certificate_arn != null ? { ingress-certificate-arn = var.ingress_certificate_arn } : {},
    var.ingress_wafv2_acl_arn != null ? { ingress-wafv2-acl-arn = var.ingress_wafv2_acl_arn } : {},
    var.ingress_host != null ? { ingress-host = var.ingress_host } : {},
    { snapshot-repository-name = var.snapshot_repository_name },
    { aws-region = var.region }
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






