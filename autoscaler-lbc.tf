# Load Balancer Controller
module "lb_controller_irsa_role" {
  count  = var.enable_irsa ? 1 : 0
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.58.0"
  
  role_name                              = var.lb_controller_role_name
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    eks = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${var.namespace}:${var.lb_controller_service_account}"]
    }
  }
}

module "cluster_autoscaler_irsa_role" {
  count   = var.enable_irsa ? 1 : 0
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.58.0"

  role_name = var.autoscaler_role_name

  # Attach AutoScalingFullAccess Policy
  role_policy_arns = {
    autoscaling = "arn:aws:iam::aws:policy/AutoScalingFullAccess"
  }

  oidc_providers = {
    eks = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${var.namespace}:${var.autoscaler_service_account}"]
    }
  }
}