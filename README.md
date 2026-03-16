# nx-infra-tf

Terraform module to provision the complete AWS infrastructure stack for NvisionX. IAM roles are created separately by [nx-iam-tf](https://github.com/Nvision-x/nx-iam-tf) and passed as inputs. This module creates Pod Identity associations that link those IAM roles to Kubernetes service accounts.

---

## Components

- **Amazon EKS** -- Managed Kubernetes cluster with Pod Identity, managed node groups, and EKS addons (CoreDNS, VPC-CNI, kube-proxy, EBS CSI, EFS CSI, Pod Identity Agent, CloudWatch)
- **Amazon RDS** -- PostgreSQL with configurable storage types (gp2/gp3/io1/io2), IOPS, autoscaling, and Performance Insights
- **Amazon OpenSearch** -- Dedicated master nodes, coordinator nodes, configurable EBS IOPS/throughput, fine-grained access control
- **Amazon EFS** -- Optional elastic filesystem for zone-independent storage
- **S3 Buckets** -- Application buckets with versioning, encryption, lifecycle policies
- **EC2 Bastion** -- Optional jump host with EKS admin access
- **EC2 NFS** -- Optional NFS server instance

---

## Architecture

```
nx-iam-tf (IAM roles, no EKS dependency)
    |
    v  role ARNs passed as inputs
nx-infra-tf (EKS + Pod Identity associations + RDS + OpenSearch + S3 + EC2)
    |
    v  cluster name/endpoint passed as inputs
nx-eks-addons-tf (Helm charts: autoscaler, LB controller)
```

---

## Pod Identity Associations

This module creates Pod Identity associations linking IAM roles to Kubernetes service accounts:

| Association | Role ARN Input | Service Account |
|---|---|---|
| EBS CSI Driver | `ebs_csi_role_arn` | `ebs-csi-controller-sa` (via EKS addon) |
| EFS CSI Driver | `efs_csi_role_arn` | `efs-csi-controller-sa` (via EKS addon) |
| Cluster Autoscaler | `cluster_autoscaler_role_arn` | configurable via `autoscaler_service_account` |
| Load Balancer Controller | `lb_controller_role_arn` | configurable via `lb_controller_service_account` |
| Postgres Backup | `postgres_backup_role_arn` | configurable via `postgres_backup_service_account` |
| App S3 Access | `app_s3_role_arn` | configurable via `app_s3_service_accounts` |
| Bedrock | `bedrock_role_arn` | configurable via `bedrock_service_accounts` |

No OIDC provider or two-step apply required. Apply nx-iam-tf first, then pass role ARNs to this module.

---

## Usage

```hcl
module "nx" {
  source = "git::https://github.com/Nvision-x/nx-infra-tf.git?ref=v2026.03.16-3"

  region          = "us-east-1"
  vpc_id          = "vpc-abc123"
  vpc_cidr_block  = "10.1.0.0/16"
  private_subnets = ["subnet-a", "subnet-b", "subnet-c"]
  tags            = { Environment = "production" }

  # EKS
  cluster_name         = "eks-production"
  cluster_version      = "1.33"
  cluster_iam_role_arn = module.nx-iam.eks_cluster_iam_role_arn
  create_iam_role      = false

  eks_managed_node_groups       = var.eks_managed_node_groups
  autoscaler_service_account    = "cluster-autoscaler"
  lb_controller_service_account = "aws-load-balancer-controller"

  # Pod Identity Role ARNs (from nx-iam-tf)
  ebs_csi_role_arn            = module.nx-iam.ebs_csi_iam_role_arn
  efs_csi_role_arn            = module.nx-iam.efs_csi_iam_role_arn
  cluster_autoscaler_role_arn = module.nx-iam.cluster_autoscaler_iam_role_arn
  lb_controller_role_arn      = module.nx-iam.lb_controller_iam_role_arn
  postgres_backup_role_arn    = module.nx-iam.postgres_backup_iam_role_arn

  # PostgreSQL
  enable_postgres  = true
  db_identifier    = "production-postgres"
  instance_class   = "db.m7g.xlarge"
  storage_type     = "io2"
  iops             = 10000

  # OpenSearch
  enable_opensearch                    = true
  domain_name                          = "production-os"
  opensearch_instance_type             = "om2.4xlarge.search"
  number_of_nodes                      = 20
  enable_masternodes                   = true
  number_of_master_nodes               = 3
  opensearch_master_instance_type      = "m7g.large.search"
  opensearch_coordinator_nodes_enabled = true
  opensearch_coordinator_node_count    = 5
  opensearch_coordinator_instance_type = "m7g.2xlarge.search"
  opensearch_ebs_iops                  = 16000
  opensearch_ebs_throughput            = 1000

  # EFS
  enable_efs = true
}
```

---

## Key Inputs

### Global
| Name | Description | Default |
|------|-------------|---------|
| `region` | AWS region | - |
| `vpc_id` | VPC ID | - |
| `private_subnets` | List of private subnet IDs | - |
| `tags` | Tags for all resources | `{}` |

### EKS
| Name | Description | Default |
|------|-------------|---------|
| `cluster_name` | EKS cluster name | - |
| `cluster_version` | Kubernetes version | - |
| `cluster_iam_role_arn` | Cluster IAM role ARN | - |
| `create_iam_role` | Create cluster IAM role (false if using nx-iam-tf) | `false` |
| `eks_managed_node_groups` | Map of node group definitions | `{}` |
| `enable_efs` | Enable EFS filesystem and CSI driver | `false` |

### Pod Identity Role ARNs
| Name | Description | Default |
|------|-------------|---------|
| `ebs_csi_role_arn` | EBS CSI driver role ARN | - |
| `efs_csi_role_arn` | EFS CSI driver role ARN | `""` |
| `cluster_autoscaler_role_arn` | Cluster Autoscaler role ARN | - |
| `lb_controller_role_arn` | Load Balancer Controller role ARN | - |
| `postgres_backup_role_arn` | Postgres backup role ARN | `""` |
| `app_s3_role_arn` | App S3 access role ARN | `""` |
| `bedrock_role_arn` | Bedrock access role ARN | `""` |

### PostgreSQL
| Name | Description | Default |
|------|-------------|---------|
| `enable_postgres` | Enable RDS PostgreSQL | - |
| `storage_type` | Storage type (gp2/gp3/io1/io2) | `"gp2"` |
| `max_allocated_storage` | Max storage for autoscaling (0 to disable) | `0` |
| `iops` | Provisioned IOPS (for io1/io2) | `null` |
| `performance_insights_retention_period` | PI retention in days | `7` |

### OpenSearch
| Name | Description | Default |
|------|-------------|---------|
| `opensearch_master_instance_type` | Master node instance type (falls back to data type) | `""` |
| `opensearch_coordinator_nodes_enabled` | Enable coordinator nodes | `false` |
| `opensearch_coordinator_node_count` | Number of coordinator nodes | `0` |
| `opensearch_coordinator_instance_type` | Coordinator node instance type | `""` |
| `opensearch_ebs_iops` | EBS provisioned IOPS | `null` |
| `opensearch_ebs_throughput` | EBS throughput (MiB/s) for gp3 | `null` |

---

## Outputs

| Name | Description |
|------|-------------|
| `eks_cluster_endpoint` | EKS control plane endpoint |
| `eks_cluster_ca` | EKS cluster CA certificate (base64) |
| `eks_cluster_name` | EKS cluster name |
| `efs_file_system_id` | EFS filesystem ID |
| `private_key_pem` | NFS EC2 private key (sensitive) |
| `bastion_private_key_pem` | Bastion EC2 private key (sensitive) |

---

## Requirements

| Name | Version |
|------|---------|
| Terraform | >= 1.5.7 |
| AWS Provider | ~> 6.0 |
| Helm Provider | ~> 3.0 |
| Kubernetes Provider | ~> 2.0 |

## Upstream Modules

| Name | Source | Version |
|------|--------|---------|
| EKS | terraform-aws-modules/eks/aws | ~> 21.0 |
| RDS | terraform-aws-modules/rds/aws | ~> 6.0 |
| OpenSearch | terraform-aws-modules/opensearch/aws | ~> 2.0 |
