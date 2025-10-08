locals {
  oidc_hostpath = replace(module.eks.cluster_oidc_issuer_url, "https://", "")
}

data "aws_iam_policy" "ebs_csi" {
  count = var.enable_irsa ? 1 : 0
  name  = "AmazonEBSCSIDriverPolicy"
}

data "aws_iam_policy_document" "ebs_irsa_trust" {
  count = var.enable_irsa ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_hostpath}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_hostpath}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi_irsa" {
  count              = var.enable_irsa ? 1 : 0
  name               = "${var.cluster_name}-ebs-csi-irsa"
  assume_role_policy = data.aws_iam_policy_document.ebs_irsa_trust[0].json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi_attach" {
  count      = var.enable_irsa ? 1 : 0
  role       = aws_iam_role.ebs_csi_irsa[0].name
  policy_arn = data.aws_iam_policy.ebs_csi[0].arn
}
