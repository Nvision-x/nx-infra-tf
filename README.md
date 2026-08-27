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
| `enable_cluster_creator_admin_permissions` | Grant the identity running terraform cluster-admin; set `false` to avoid access-entry/KMS drift when plan/apply use different IAM principals | `true` |
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
| `opensearch_advanced_options` | Extra `advanced_options` merged over computed defaults (consumer keys win); codify overrides like `override_main_response_version` to avoid phantom drift | `{}` |

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
| `monitoring_sns_topic_arn` | Alarm SNS topic ARN (null when monitoring disabled) |
| `monitoring_dashboard_name` | CloudWatch dashboard name (null when disabled) |

---

## Monitoring

CloudWatch alarms for every stateful / operationally-critical resource, wired to
an SNS topic that fans out to email and to Slack via Amazon Q Developer in chat
applications (formerly AWS Chatbot). All monitoring variables live in
[`variables-monitoring.tf`](variables-monitoring.tf); resources in
[`cloudwatch-monitoring.tf`](cloudwatch-monitoring.tf).

Disabled by default (`enable_monitoring = false`) so it never surprises
non-production consumers of this module — production turns it on.

```hcl
# --- turn on monitoring (production) ---
enable_monitoring       = true
monitoring_alarm_emails = ["devops@nvisionx.ai"]

# Slack via Amazon Q / AWS Chatbot (one-time workspace auth in console — see below)
monitoring_slack_workspace_id = "T0XXXXXXX"
monitoring_slack_channel_id   = "C0XXXXXXX"

# Tune any threshold (all have sane defaults)
rds_cpu_threshold                 = 85
opensearch_jvm_pressure_threshold = 80
```

**What's alarmed**

- **EKS / Container Insights** — node CPU / memory / disk, failed-node count (via the `amazon-cloudwatch-observability` addon this module installs)
- **RDS** — CPU, freeable memory, free storage, connections, read/write latency, disk queue depth, swap
- **OpenSearch** — cluster status red/yellow, free storage, CPU, JVM & old-gen pressure, writes-blocked, node count, snapshot failure, KMS error, 5xx; plus dedicated-master CPU / JVM / reachability
- **Neptune** — CPU, serverless capacity vs the NCU ceiling, request-queue backlog
- **EC2 bastion / NFS** — status-check failures, CPU
- **EFS** — PercentIOLimit

Every category has its own enable/disable flag (`monitoring_rds_enabled`, etc.),
and an alarm is created only when monitoring is on **and** the underlying
resource is enabled. An optional single-pane dashboard
(`enable_monitoring_dashboard`, default on) summarizes everything.

**Slack delivery — Amazon Q / AWS Chatbot**

Set `monitoring_slack_workspace_id` + `monitoring_slack_channel_id`. Amazon Q
subscribes to the SNS topic natively (no Lambda). It requires a **one-time**
manual step that can't be done in Terraform: in the Amazon Q Developer / AWS
Chatbot console, add the AWS app to your Slack workspace and authorize it, then
copy the workspace (team) ID and channel ID into the two variables. Until both
IDs are set, the SNS pipeline still deploys and the channel config is skipped.

> Amazon Q / Chatbot uses the Slack **app** (OAuth), not an incoming webhook —
> there's no webhook URL to configure. A read-only guardrail is applied so chat
> can view but never mutate resources.

---

## Manual prerequisites

A few things this module does not (and cannot) do for you:

- **S3 Vectors indexes** — `aws_s3vectors_vector_bucket` creates the bucket only. Indexes carry dimension and distance-metric choices that are per-use-case and belong with the application that owns the data; create them from the app (boto3 / SDK) or with a small bootstrap script.
- **Neptune IAM-auth bootstrap** — Newly created Neptune clusters need an initial role/identity mapped to the database. The cluster comes up with IAM auth enabled but no app principal granted; load the first identity from a bastion or one-shot pod using `awscurl` / the Neptune CLI.

> Bedrock note: AWS no longer requires a per-model console grant to invoke foundation models — IAM permissions alone are sufficient.

---

## Bastion tailscale bootstrap

Off by default. Turn it on per env:

```hcl
enable_tailscale_bootstrap = true
tailscale_hostname         = "nx-development-exitnode"
# tailscale_advertise_routes defaults to vpc_cidr_block
```

Terraform creates `/nx/tailscale/bastion-authkey` as a SecureString holding
`PLACEHOLDER` and never touches the value again. Generate a **tagged, reusable**
auth key in the tailscale admin console and paste it in:

```bash
aws ssm put-parameter --name /nx/tailscale/bastion-authkey \
  --type SecureString --value tskey-auth-... --overwrite
```

From then on a rebuilt bastion registers itself on first boot. The key is read at
boot only — user-data carries the parameter name, never the key.

Moving an existing user-owned node onto the tag needs `TS_FORCE=true`, which re-auths
a node that is already up:

```bash
sudo TS_FORCE=true TS_HOSTNAME=nx-development-exitnode TS_ROUTES=10.5.0.0/16 \
  /usr/local/bin/tailscale-bootstrap.sh
```

Existing hosts (and customer on-prem nodes with no AWS) run the same script by hand:

```bash
# AWS host: key comes from SSM
sudo TS_HOSTNAME=nx-development-exitnode TS_ROUTES=10.5.0.0/16 \
  /usr/local/bin/tailscale-bootstrap.sh

# on-prem: pass the key directly
sudo TS_AUTHKEY=tskey-auth-... TS_HOSTNAME=nx-ionis-exitnode \
  /usr/local/bin/tailscale-bootstrap.sh
```

Tagged nodes are owned by the tailnet, not by whoever authenticated them, and their
keys do not expire — which is what took `nx-development-exitnode` offline on
2026-08-10. The `tag:exit-node` tag and its `tagOwner` must exist in the tailnet ACL
before the auth key will work.

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

---

## No IAM in this module

This module creates no IAM identities. Roles, policies and attachments live in
[nx-iam-tf](https://github.com/Nvision-x/nx-iam-tf); this module consumes their
ARNs as inputs. A CI check (`.github/workflows/no-iam.yaml`) fails any PR that
adds an `aws_iam_*` resource.

Resource policies are not affected — `aws_sns_topic_policy`,
`aws_s3_bucket_policy` and friends belong with the resource they protect.

The awkward case is an ARN that only exists once the resource does. Build it in
nx-iam-tf from plan-time-known values rather than feeding an output backwards
into that module; see `knowledge-hub-data-access.tf` there.
