module "nx" {
  # source = "git::https://github.com/Nvision-x/nx-infra-tf.git"
  source = "../.."

  # --------------------- Global/Provider ---------------------

  region          = var.region
  vpc_cidr_block  = var.vpc_cidr_block
  vpc_id          = var.vpc_id
  private_subnets = var.private_subnets
  tags            = var.tags

  # --------------------- EKS ---------------------

  cluster_name         = var.cluster_name
  cluster_version      = var.cluster_version
  cluster_iam_role_arn = var.cluster_iam_role_arn

  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  eks_managed_node_groups              = var.eks_managed_node_groups
  cluster_endpoint_private_access      = var.cluster_endpoint_private_access
  cluster_endpoint_public_access       = var.cluster_endpoint_public_access
  enable_irsa                          = var.enable_irsa
  create_iam_role                      = var.create_iam_role

  # --------------------- PostgreSQL ---------------------

  allocated_storage             = var.allocated_storage
  allow_major_version_upgrade   = var.allow_major_version_upgrade
  apply_immediately             = var.apply_immediately
  backup_retention_period       = var.backup_retention_period
  backup_window                 = var.backup_window
  copy_tags_to_snapshot         = var.copy_tags_to_snapshot
  db_identifier                 = var.db_identifier
  db_name                       = var.db_name
  db_security_group_description = "Allow PostgreSQL access"
  db_security_group_name        = var.db_security_group_name
  db_subnet_group_name          = var.db_subnet_group_name
  enable_postgres               = var.enable_postgres
  instance_class                = var.instance_class
  maintenance_window            = var.maintenance_window
  manage_master_user_password   = var.manage_master_user_password
  parameter_group_name          = var.parameter_group_name
  performance_insights_enabled  = var.performance_insights_enabled
  postgres_version              = var.postgres_version
  skip_final_snapshot           = var.skip_final_snapshot
  subnet_group_description      = var.subnet_group_description
  username                      = var.username
  postgres_ingress_rules        = var.postgres_ingress_rules

  # --------------------- OpenSearch ---------------------

  domain_name                           = var.domain_name
  ebs_volume_size                       = var.ebs_volume_size
  ebs_volume_type                       = var.ebs_volume_type
  enable_masternodes                    = var.enable_masternodes
  enable_opensearch                     = var.enable_opensearch
  engine_version                        = var.engine_version
  master_user_name                      = var.master_user_name
  number_of_master_nodes                = var.number_of_master_nodes
  number_of_nodes                       = var.number_of_nodes
  opensearch_instance_type              = var.opensearch_instance_type
  opensearch_security_group_description = "os-sg"
  opensearch_security_group_name        = var.opensearch_security_group_name
  opensearch_subnet_ids                 = var.opensearch_subnet_ids
  opensearch_ingress_rules              = var.opensearch_ingress_rules

  # --------------------- NFS ---------------------

  ami                   = var.ami
  disk_size             = var.disk_size
  ec2_name              = var.ec2_name
  enable_nfs            = var.enable_nfs
  existing_pem          = var.existing_pem
  instance_type         = var.instance_type
  key_name              = var.key_name
  nfs_private_subnet_id = var.nfs_private_subnet_id
  security_group_name   = var.security_group_name
  nfs_ingress_rules     = var.nfs_ingress_rules

  # --------------------- Bastion ---------------------

  bastion_ami                 = var.bastion_ami
  bastion_disk_size           = var.bastion_disk_size
  bastion_ec2_name            = var.bastion_ec2_name
  enable_bastion              = var.enable_bastion
  bastion_existing_pem        = var.bastion_existing_pem
  bastion_instance_type       = var.bastion_instance_type
  bastion_key_name            = var.bastion_key_name
  bastion_public_subnet_id    = var.bastion_public_subnet_id
  bastion_security_group_name = var.bastion_security_group_name
  bastion_ingress_rules       = var.bastion_ingress_rules
  bastion_eks_admin_role_arn  = var.bastion_eks_admin_role_arn
  bastion_profile_name        = var.bastion_profile_name
}

module "eks_addons" {

  source = "git::https://github.com/Nvision-x/nx-eks-addons-tf.git"
  # source = "../../../nx-eks-addons-tf"

  # --------------------- EKS Addons ---------------------

  autoscaler_role_name          = var.autoscaler_role_name
  autoscaler_service_account    = var.autoscaler_service_account
  lb_controller_role_name       = var.lb_controller_role_name
  lb_controller_service_account = var.lb_controller_service_account
  lb_controller_role_arn        = var.lb_controller_role_arn
  cluster_autoscaler_role_arn   = var.cluster_autoscaler_role_arn

  # --------------------- EKS Cluster ---------------------

  cluster_name = module.nx.eks_cluster_name
  namespace    = "kube-system"
  region       = var.region
  vpc_id       = var.vpc_id

  providers = {
    helm    = helm.eks
    kubectl = kubectl.eks
  }

}
