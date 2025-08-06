resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.37.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnets

  cluster_endpoint_private_access          = var.cluster_endpoint_private_access
  cluster_endpoint_public_access           = var.cluster_endpoint_public_access
  cluster_endpoint_public_access_cidrs     = var.cluster_endpoint_public_access_cidrs
  enable_irsa                              = var.enable_irsa
  create_iam_role                          = var.create_iam_role
  iam_role_arn                             = var.cluster_iam_role_arn
  eks_managed_node_groups                  = var.eks_managed_node_groups
  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    coredns                         = {}
    eks-pod-identity-agent          = {}
    kube-proxy                      = {}
    vpc-cni                         = {}
    aws-ebs-csi-driver              = {}
    amazon-cloudwatch-observability = {}
  }
  eks_managed_node_group_defaults = {
    disk_size       = 50
    disk_encryption = true
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

resource "aws_eks_access_policy_association" "access_policy" {
  count         = var.eks_access_principal_arn != null ? 1 : 0
  cluster_name  = module.eks.cluster_name
  principal_arn = var.eks_access_principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}

