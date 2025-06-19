# ------------------------ Global/Provider Config ------------------------

variable "region" {
  description = "The AWS region to deploy resources into"
  type        = string
}

# ----------------------------- Networking -------------------------------

variable "private_subnets" {
  description = "List of private subnets in the VPC"
  type        = list(string)
}

variable "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  type        = string
}

variable "vpc_id" {
  description = "The ID of the VPC"
  type        = string
}

# ----------------------------- EKS --------------------------------------

variable "autoscaler_role_name" {
  description = "Name of IAM role for cluster autoscaler"
  type        = string
}

variable "autoscaler_service_account" {
  description = "Service account name for cluster autoscaler"
  type        = string
}

variable "cluster_name" {
  description = "EKS Cluster Name"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
}

variable "lb_controller_role_name" {
  description = "Name of IAM role for load balancer controller"
  type        = string
}

variable "lb_controller_service_account" {
  description = "Service account name for load balancer controller"
  type        = string
}

variable "namespace" {
  description = "Namespace where resources will be created"
  type        = string
  default     = "kube-system"
}

variable "oidc_provider_arn" {
  description = "oidc provider arn"
  type        = string
}

variable "cluster_iam_role_arn" {
  description = "IAM role ARN for the EKS cluster"
  type        = string
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks allowed to access the EKS public endpoint"
  type        = list(string)
}

variable "eks_managed_node_groups" {
  description = "Map of EKS managed node group definitions to create"
  type        = any
  default     = {}
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

variable "create_iam_role" {
  description = "Whether to create a new IAM role for the EKS cluster. Set to false if IAM is managed externally."
  type        = bool
  default     = false
}

# ----------------------------- Bastion --------------------------------------

variable "enable_bastion" {
  description = "Flag to control Bastion resource creation"
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

variable "ami" {
  description = "The AMI ID for the EC2 instance"
  type        = string
}

variable "disk_size" {
  description = "Size of the root volume in GB"
  type        = number
  default     = 100
}

variable "ec2_name" {
  description = "The Name tag for the EC2 instance"
  type        = string
}

variable "enable_nfs" {
  description = "Flag to control EC2-related resource creation"
  type        = bool
}

variable "existing_pem" {
  description = "Existing PEM key to use, if provided"
  type        = string
  default     = ""
}

variable "instance_type" {
  description = "Instance type for the EC2 instance"
  type        = string
}

variable "key_name" {
  description = "Name of the key pair to use for the EC2 instance"
  type        = string
}

variable "nfs_private_subnet_id" {
  description = "Private subnet ID where the EC2 instance will be deployed"
  type        = string
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


variable "security_group_name" {
  description = "The name of the security group for the EC2 instance"
  type        = string
}

# ----------------------------- PostgreSQL -------------------------------

variable "allocated_storage" {
  description = "The size of the database storage in GB"
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

variable "backup_retention_period" {
  description = "The number of days to retain backups for"
  type        = number
  default     = 7
}

variable "backup_window" {
  description = "Preferred backup window"
  type        = string
  default     = "03:00-06:00"
}

variable "db_identifier" {
  description = "The identifier for the RDS instance"
  type        = string
}

variable "db_name" {
  description = "The name of the database"
  type        = string
}

variable "db_security_group_name" {
  description = "The name of the database security group"
  type        = string
}

variable "db_subnet_group_name" {
  description = "The name of the database subnet group"
  type        = string
}

variable "enable_postgres" {
  description = "Flag to enable/disable PostgreSQL and related resources"
  type        = bool
}

variable "instance_class" {
  description = "The class of the RDS instance"
  type        = string
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

variable "postgres_password" {
  description = "The password for the database"
  type        = string
  sensitive   = true
  default     = null
}

variable "postgres_version" {
  description = "PostgreSQL version for the RDS instance"
  type        = string
}

variable "skip_final_snapshot" {
  description = "Whether to skip the final snapshot before deleting the instance"
  type        = bool
  default     = false
}

variable "subnet_group_description" {
  description = "Description for the RDS subnet group"
  type        = string
  default     = "Subnet group for RDS instances"
}

variable "username" {
  description = "The username for the database"
  type        = string
}

variable "copy_tags_to_snapshot" {
  description = "Whether to copy tags to snapshots"
  type        = bool
  default     = true
}

# --------------------------- OpenSearch ---------------------------------

variable "domain_name" {
  description = "The domain name for the OpenSearch cluster"
  type        = string
}

variable "ebs_volume_size" {
  description = "The size of the EBS volume in GB for OpenSearch"
  type        = string
}

variable "ebs_volume_type" {
  description = "EBS volume type for OpenSearch nodes"
  type        = string
  default     = "gp3"
}

variable "enable_masternodes" {
  description = "Enable master nodes for OpenSearch"
  type        = bool
}

variable "enable_opensearch" {
  description = "Flag to enable or disable OpenSearch and related resources"
  type        = bool
}

variable "engine_version" {
  description = "The version of the OpenSearch engine"
  type        = string
}

variable "master_user_name" {
  description = "The username for the OpenSearch admin"
  type        = string
}

variable "number_of_master_nodes" {
  description = "Number of master nodes for OpenSearch"
  type        = number
}

variable "number_of_nodes" {
  description = "Number of data nodes for OpenSearch"
  type        = number
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

variable "opensearch_instance_type" {
  description = "The type of instance for the OpenSearch cluster"
  type        = string
}

variable "opensearch_master_user_password" {
  description = "The password for the OpenSearch admin"
  type        = string
  sensitive   = true
  default     = null
}

variable "opensearch_security_group_name" {
  description = "The name of the security group for OpenSearch"
  type        = string
}

variable "opensearch_subnet_ids" {
  description = "List of private subnet IDs for OpenSearch"
  type        = list(string)
}

# ----------------------------- Tags --------------------------------------

variable "tags" {
  description = "A map of tags to assign to all applicable resources"
  type        = map(string)
  default = {
    Project = "nx-app"
  }
}
