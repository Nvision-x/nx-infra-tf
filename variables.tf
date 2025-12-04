# ------------------------ Global/Provider Config ------------------------

variable "region" {
  description = "The AWS region to deploy resources into"
  type        = string
}

variable "docker_hub_username" {
  type        = string
  default     = ""
  description = "Docker Hub username"
}

variable "docker_hub_token" {
  type        = string
  description = "Docker Hub read-only access token"
  sensitive   = true
}

variable "github_cr_username" {
  type        = string
  default     = ""
  description = "GitHub Container Registry username"
}

variable "github_cr_token" {
  type        = string
  default     = ""
  description = "GitHub Container Registry personal access token"
  sensitive   = true
}

# ----------------------------- Networking -------------------------------

variable "vpc_id" {
  description = "The ID of the VPC"
  type        = string
}

variable "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  type        = string
}

variable "private_subnets" {
  description = "List of private subnets in the VPC"
  type        = list(string)
}

# ----------------------------- EKS --------------------------------------

variable "cluster_name" {
  description = "EKS Cluster Name"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
}

variable "cluster_iam_role_arn" {
  description = "Cluster IAM role ARN"
  type        = string
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks which can access the Amazon EKS public API server endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_endpoint_private_access" {
  description = "Enable private access to EKS cluster endpoint"
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access" {
  description = "Enable public access to EKS cluster endpoint"
  type        = bool
  default     = true
}

variable "enable_irsa" {
  description = "Enable IRSA (IAM Roles for Service Accounts). OIDC provider will be created by IAM module."
  type        = bool
  default     = false
}

variable "ebs_csi_irsa_role_arn" {
  type        = string
  description = "IAM role ARN for EBS CSI controller service account (IRSA)"
  default     = ""
}

variable "create_iam_role" {
  description = "Whether to create a new IAM role for the EKS cluster. Set to false if IAM is managed externally."
  type        = bool
  default     = false
}

variable "eks_managed_node_groups" {
  description = "Map of EKS managed node group definitions to create"
  type        = any
  default     = {}
}

# variables.tf
variable "eks_access_principal_arn" {
  description = "IAM Role or User ARN to grant access to the EKS cluster"
  type        = string
  default     = null
}

// for oidc 

variable "namespace" {
  description = "Namespace where resources will be created"
  type        = string
  default     = "kube-system"
}

variable "autoscaler_role_name" {
  description = "Name of IAM role for cluster autoscaler"
  type        = string
  default     = ""
}

variable "autoscaler_service_account" {
  description = "Service account name for cluster autoscaler"
  type        = string
  default     = ""
}

variable "lb_controller_role_name" {
  description = "Name of IAM role for load balancer controller"
  type        = string
  default     = ""
}

variable "lb_controller_service_account" {
  description = "Service account name for load balancer controller"
  type        = string
  default     = ""
}


# ----------------------------- Bastion --------------------------------------

variable "enable_bastion" {
  description = "Flag to control Bastion resource creation"
  type        = bool
  default     = false
}

variable "enable_post_deployment" {
  description = "Flag to enable post-deployment setup (snapshot repository registration, kubectl configuration, etc.)"
  type        = bool
  default     = false
}

variable "bastion_ingress_rules" {
  description = "List of ingress rules for Bastion EC2 security group"
  type = list(object({
    description = string
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
  }))
  default = []
}

variable "bastion_public_subnet_id" {
  description = "Private subnet ID where the Bastion EC2 instance will be deployed"
  type        = string
  default     = ""
}

variable "bastion_security_group_description" {
  description = "Description for the Bastion EC2 security group"
  type        = string
  default     = "Allow SSH access"
}

variable "bastion_key_name" {
  description = "Name of the key pair to use for the Bastion EC2 instance"
  type        = string
  default     = ""
}

variable "bastion_instance_type" {
  description = "Instance type for the EC2 instance"
  type        = string
  default     = "t3.small"
}

variable "bastion_disk_size" {
  description = "Size of the root volume in GB"
  type        = number
  default     = 8
}

variable "bastion_ami" {
  description = "The AMI ID for the EC2 instance"
  type        = string
}

variable "bastion_ec2_name" {
  description = "The Name tag for the EC2 instance"
  type        = string
  default     = "nx-bastion-host"
}

variable "bastion_security_group_name" {
  description = "The name of the security group for the EC2 instance"
  type        = string
}

variable "bastion_existing_pem" {
  description = "Existing PEM key to use, if provided"
  type        = string
  default     = ""
}

# ----------------------------- NFS --------------------------------------

variable "enable_nfs" {
  description = "Flag to control EC2-related resource creation"
  type        = bool
}

variable "nfs_ingress_rules" {
  description = "List of ingress rules for NFS EC2 security group"
  type = list(object({
    description = string
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
  }))
  default = []
}


variable "nfs_private_subnet_id" {
  description = "Private subnet ID where the EC2 instance will be deployed"
  type        = string
}

variable "nfs_security_group_description" {
  description = "Description for the NFS EC2 security group"
  type        = string
  default     = "Allow SSH and NFS access"
}

variable "key_name" {
  description = "Name of the key pair to use for the EC2 instance"
  type        = string
}

variable "instance_type" {
  description = "Instance type for the EC2 instance"
  type        = string
}

variable "disk_size" {
  description = "Size of the root volume in GB"
  type        = number
  default     = 100
}

variable "ami" {
  description = "The AMI ID for the EC2 instance"
  type        = string
}

variable "ec2_name" {
  description = "The Name tag for the EC2 instance"
  type        = string
}

variable "security_group_name" {
  description = "The name of the security group for the EC2 instance"
  type        = string
}

variable "existing_pem" {
  description = "Existing PEM key to use, if provided"
  type        = string
  default     = ""
}



# ----------------------------- PostgreSQL -------------------------------

variable "subnet_group_description" {
  description = "Description for the RDS subnet group"
  type        = string
  default     = "Managed by Terraform"
}

variable "db_security_group_description" {
  description = "Description for the RDS security group"
  type        = string
  default     = "Managed by Terraform"
}

variable "enable_postgres" {
  description = "Flag to enable/disable PostgreSQL and related resources"
  type        = bool
}

variable "instance_class" {
  description = "The class of the RDS instance"
  type        = string
}

variable "db_name" {
  description = "The name of the database"
  type        = string
}

variable "username" {
  description = "The username for the database"
  type        = string
}

# Variable for existing PostgreSQL password (optional)
variable "existing_postgres_password" {
  description = "Existing PostgreSQL password to use instead of generating a new one"
  type        = string
  sensitive   = true
  default     = ""
}

variable "allocated_storage" {
  description = "The size of the database storage in GB"
  type        = string
}

variable "db_identifier" {
  description = "The identifier for the RDS instance"
  type        = string
}

variable "db_subnet_group_name" {
  description = "The name of the database subnet group"
  type        = string
}

variable "db_security_group_name" {
  description = "The name of the database security group"
  type        = string
}

variable "postgres_version" {
  description = "PostgreSQL version for the RDS instance"
  type        = string
}

variable "allow_major_version_upgrade" {
  description = "Whether to allow major version upgrades during updates"
  type        = bool
  default     = false
}

variable "apply_immediately" {
  description = "Whether to apply changes immediately or during the next maintenance window"
  type        = bool
  default     = false
}

variable "backup_window" {
  description = "Preferred backup window"
  type        = string
  default     = "03:00-06:00"
}

variable "copy_tags_to_snapshot" {
  description = "Whether to copy tags to snapshots"
  type        = bool
  default     = true
}

variable "maintenance_window" {
  description = "Preferred maintenance window"
  type        = string
  default     = "mon:00:00-mon:03:00"
}

variable "manage_master_user_password" {
  description = "Whether the master user password is managed by RDS automatically"
  type        = bool
  default     = false
}

variable "parameter_group_name" {
  description = "Name of the DB parameter group to associate"
  type        = string
  default     = null
}

variable "skip_final_snapshot" {
  description = "Whether to skip the final snapshot before deleting the instance"
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "The number of days to retain backups for"
  type        = number
  default     = 7
}

variable "performance_insights_enabled" {
  description = "Specifies whether Performance Insights are enabled"
  type        = bool
  default     = false
}

variable "postgres_ingress_rules" {
  description = "List of ingress rules"
  type = list(object({
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
  }))
  default = []
}

variable "postgres_backup_service_account" {
  description = "Kubernetes service account name for PostgreSQL backup"
  type        = string
  default     = "databases-postgres-backup-sa"
}

variable "postgres_backup_namespace" {
  description = "Kubernetes namespace for PostgreSQL backup service account"
  type        = string
  default     = "default"
}


# --------------------------- OpenSearch ---------------------------------

variable "enable_opensearch" {
  description = "Flag to enable or disable OpenSearch and related resources"
  type        = bool
}

variable "master_user_name" {
  description = "The username for the OpenSearch admin"
  type        = string
}

# Variable for existing OpenSearch password (optional)
variable "existing_opensearch_password" {
  description = "Existing OpenSearch password to use instead of generating a new one"
  type        = string
  sensitive   = true
  default     = ""
}

variable "opensearch_instance_type" {
  description = "The type of instance for the OpenSearch cluster"
  type        = string
}

variable "opensearch_security_group_name" {
  description = "The name of the security group for OpenSearch"
  type        = string
}
variable "opensearch_security_group_description" {
  description = "Description for the OpenSearch security group"
  type        = string
  default     = "Managed by Terraform"
}

variable "domain_name" {
  description = "The domain name for the OpenSearch cluster"
  type        = string
}

variable "ebs_volume_size" {
  description = "The size of the EBS volume in GB for OpenSearch"
  type        = string
}

variable "engine_version" {
  description = "The version of the OpenSearch engine"
  type        = string
}

variable "enable_masternodes" {
  description = "Enable master nodes for OpenSearch"
  type        = bool
}

variable "number_of_master_nodes" {
  description = "Number of master nodes for OpenSearch"
  type        = number
}

variable "number_of_nodes" {
  description = "Number of data nodes for OpenSearch"
  type        = number
}

variable "ebs_volume_type" {
  description = "EBS volume type for OpenSearch nodes"
  type        = string
  default     = "gp3"
}

variable "opensearch_ingress_rules" {
  description = "List of ingress rules"
  type = list(object({
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
  }))
  default = []
}

variable "zone_awareness_enabled" {
  description = "Whether to enable zone awareness for OpenSearch cluster"
  type        = bool
  default     = false
}

variable "availability_zone_count" {
  description = "Number of Availability Zones to use if zone awareness is enabled"
  type        = number
  default     = 1
}

variable "opensearch_subnet_ids" {
  description = "List of private subnet IDs for OpenSearch"
  type        = list(string)
}

variable "opensearch_log_publishing_options" {
  description = "List of log publishing options for OpenSearch"
  type = list(object({
    log_type = string
  }))
  default = []
}

variable "auto_software_update_enabled" {
  description = "Whether automatic software updates are enabled"
  type        = bool
  default     = false
}

variable "bastion_eks_admin_role_arn" {
  description = "ARN of the Bastion IAM role to grant EKS access"
  type        = string
  default     = ""
}

variable "bastion_profile_name" {
  description = "Name of the IAM instance profile for Bastion"
  type        = string
  default     = ""
}

variable "bastion_user_name" {
  description = "SSH user name for the bastion host (e.g., ec2-user for Amazon Linux, ubuntu for Ubuntu)"
  type        = string
  default     = "ec2-user"
}

variable "s3_force_destroy" {
  description = "Whether to force destroy the S3 bucket and its contents on deletion"
  type        = bool
  default     = false
}

variable "enable_security_hub_controls" {
  description = "Enable Security Hub compliance resources (CloudTrail S3 data events, KMS encryption, access logging)"
  type        = bool
  default     = true
}

variable "cloudtrail_log_all_s3_buckets" {
  description = "When true, CloudTrail logs object-level events for ALL S3 buckets in the account (required for S3.22/S3.23 compliance). When false, only logs NvisionX managed buckets. Set to false for customer deployments where customers have their own buckets."
  type        = bool
  default     = true
}

variable "snapshot_role_arn" {
  description = "ARN of the IAM role for OpenSearch snapshots (if created outside this module)"
  type        = string
  default     = ""
}

variable "snapshot_repository_name" {
  description = "Name of the OpenSearch snapshot repository"
  type        = string
  default     = "manual-snapshots"
}


# --------------------- Ingress -------------------------

variable "ingress_internet_facing" {
  description = "Ingress scheme: internet-facing or internal"
  type        = string
  default     = null
  validation {
    condition     = var.ingress_internet_facing == null || contains(["internet-facing", "internal"], var.ingress_internet_facing)
    error_message = "Must be either null, 'internet-facing', or 'internal'."
  }
}

variable "ingress_certificate_arn" {
  description = "ACM cert ARN for ingress"
  type        = string
  default     = null
}

variable "ingress_wafv2_acl_arn" {
  description = "WAFv2 Web ACL ARN to associate with ingress/ALB"
  type        = string
  default     = null
}

variable "ingress_host" {
  description = "Hostname (FQDN) for ingress"
  type        = string
  default     = null
}


# --------------------- Tag -----------------------------

variable "tags" {
  description = "A map of tags to assign to all applicable resources"
  type        = map(string)
  default = {
    Project = "nx-app"
  }
}

# --------------------- Bedrock Service Accounts -----------------------------

variable "enable_bedrock_service_accounts" {
  description = "Enable creation of Kubernetes ServiceAccounts for Bedrock access"
  type        = bool
  default     = false
}

variable "bedrock_service_accounts" {
  description = "List of namespace:serviceaccount pairs to create for Bedrock access. Example: ['default:bedrock-app', 'production:ai-service']"
  type        = list(string)
  default     = []
}

variable "bedrock_irsa_role_arn" {
  description = "IAM Role ARN for Bedrock IRSA (used when enable_bedrock_irsa=false, i.e., role created externally in nx-iam-tf)"
  type        = string
  default     = ""
}

variable "create_bedrock_namespaces" {
  description = "Whether to automatically create namespaces for Bedrock service accounts if they don't exist"
  type        = bool
  default     = false
}

################################################################################
# Bedrock IRSA Configuration
################################################################################

variable "enable_bedrock_irsa" {
  description = <<-EOF
    Enable Bedrock IRSA role creation in nx-infra-tf.

    Deployment Patterns:
    1. Full Auto Deployment: Set to TRUE - creates IRSA role here in nx-infra-tf
    2. IAM Separation: Set to FALSE - creates IRSA role in nx-iam-tf instead
       (3-stage: deploy nx-iam without IRSA → deploy nx-infra → redeploy nx-iam with IRSA)

    Default is FALSE (disabled).
  EOF
  type        = bool
  default     = false
}

variable "bedrock_role_name" {
  description = "Name of IAM role for Bedrock access. Required if enable_bedrock_irsa is true."
  type        = string
  default     = ""
}

################################################################################
# Bedrock Capabilities - Control which API operations are allowed
################################################################################

variable "bedrock_capabilities" {
  description = <<-EOF
    List of Bedrock capabilities to enable (only applies when enable_bedrock_irsa = true).
    Available options:
    - "invoke"          : Basic model invocation (InvokeModel)
    - "streaming"       : Streaming responses (InvokeModelWithResponseStream)
    - "model_catalog"   : Read model information (ListFoundationModels, GetFoundationModel)
    - "agents"          : Bedrock Agents runtime (InvokeAgent)
    - "knowledge_bases" : Knowledge base access (Retrieve, RetrieveAndGenerate)
    - "guardrails"      : Apply guardrails (ApplyGuardrail)

    Default includes basic invocation, streaming, and model catalog access.
  EOF
  type        = list(string)
  default     = ["invoke", "streaming", "model_catalog"]

  validation {
    condition = alltrue([
      for cap in var.bedrock_capabilities :
      contains(["invoke", "streaming", "model_catalog", "agents", "knowledge_bases", "guardrails"], cap)
    ])
    error_message = "Invalid capability. Valid options: invoke, streaming, model_catalog, agents, knowledge_bases, guardrails"
  }
}

################################################################################
# Bedrock Model Provider Filtering
################################################################################

variable "bedrock_excluded_providers" {
  description = <<-EOF
    List of model providers to EXCLUDE from access.
    Only applies when enable_bedrock_irsa = true.

    Available providers:
    - "anthropic"     : Anthropic Claude models
    - "amazon"        : Amazon Titan models
    - "ai21"          : AI21 Labs Jurassic models
    - "cohere"        : Cohere Command models
    - "meta"          : Meta Llama models
    - "mistral"       : Mistral AI models
    - "stability"     : Stability AI image models

    Example: ["anthropic", "cohere"] will block Anthropic and Cohere models
    Note: This is ignored if bedrock_use_custom_model_arns = true
  EOF
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for provider in var.bedrock_excluded_providers :
      contains(["anthropic", "amazon", "ai21", "cohere", "meta", "mistral", "stability"], provider)
    ])
    error_message = "Invalid provider. Valid options: anthropic, amazon, ai21, cohere, meta, mistral, stability"
  }
}

variable "bedrock_allowed_providers" {
  description = <<-EOF
    List of model providers to ALLOW access to. If empty, all providers are allowed (except those in excluded_providers).
    Only applies when enable_bedrock_irsa = true.

    Available providers: anthropic, amazon, ai21, cohere, meta, mistral, stability

    Example: ["amazon", "ai21"] will ONLY allow Amazon and AI21 models
    Note: bedrock_excluded_providers is applied after this filter
    Note: This is ignored if bedrock_use_custom_model_arns = true
  EOF
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for provider in var.bedrock_allowed_providers :
      contains(["anthropic", "amazon", "ai21", "cohere", "meta", "mistral", "stability"], provider)
    ])
    error_message = "Invalid provider. Valid options: anthropic, amazon, ai21, cohere, meta, mistral, stability"
  }
}

variable "bedrock_use_custom_model_arns" {
  description = "Set to true to use bedrock_custom_model_arns instead of auto-generated ARNs based on provider filters."
  type        = bool
  default     = false
}

variable "bedrock_custom_model_arns" {
  description = <<-EOF
    Custom list of Bedrock model ARNs (only used if bedrock_use_custom_model_arns = true). Examples:
    - All models: ["arn:aws:bedrock:*::foundation-model/*"]
    - Specific model family: ["arn:aws:bedrock:*::foundation-model/anthropic.claude*"]
  EOF
  type        = list(string)
  default     = ["arn:aws:bedrock:*::foundation-model/*"]
}

variable "bedrock_allowed_regions" {
  description = "List of AWS regions where Bedrock API calls are allowed."
  type        = list(string)
  default     = ["us-east-1", "us-west-2"]
}

################################################################################
# Bedrock Advanced Features - ARNs for Agents, Knowledge Bases, Guardrails
################################################################################

variable "bedrock_agent_arns" {
  description = <<-EOF
    List of Bedrock Agent ARNs allowed for access (required if 'agents' capability is enabled).
    Examples:
    - All agents: ["arn:aws:bedrock:*:*:agent/*"]
    - Specific agent: ["arn:aws:bedrock:us-east-1:123456789012:agent/AGENT123"]
  EOF
  type        = list(string)
  default     = ["arn:aws:bedrock:*:*:agent/*"]
}

variable "bedrock_knowledge_base_arns" {
  description = <<-EOF
    List of Bedrock Knowledge Base ARNs allowed for access (required if 'knowledge_bases' capability is enabled).
    Examples:
    - All knowledge bases: ["arn:aws:bedrock:*:*:knowledge-base/*"]
    - Specific KB: ["arn:aws:bedrock:us-east-1:123456789012:knowledge-base/KB123"]
  EOF
  type        = list(string)
  default     = ["arn:aws:bedrock:*:*:knowledge-base/*"]
}

variable "bedrock_guardrail_arns" {
  description = <<-EOF
    List of Bedrock Guardrail ARNs (required if 'guardrails' capability is enabled).
    Examples:
    - All guardrails: ["arn:aws:bedrock:*:*:guardrail/*"]
    - Specific guardrail: ["arn:aws:bedrock:us-east-1:123456789012:guardrail/GUARD123"]
  EOF
  type        = list(string)
  default     = ["arn:aws:bedrock:*:*:guardrail/*"]
}

