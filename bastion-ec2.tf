

# Security Group for EC2
resource "aws_security_group" "bastion_ec2_sg" {
  count = var.enable_bastion ? 1 : 0
  name  = var.bastion_security_group_name

  description = var.bastion_security_group_description
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.bastion_ingress_rules
    content {
      description = ingress.value.description
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = var.tags
}

# Generate TLS key only if no PEM is provided
resource "tls_private_key" "bastion_ec2_key" {
  count     = var.enable_bastion && var.bastion_existing_pem == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Key Pair
resource "aws_key_pair" "bastion_ec2_key" {
  count      = var.enable_bastion ? 1 : 0
  key_name   = var.bastion_key_name
  public_key = var.bastion_existing_pem == "" ? tls_private_key.bastion_ec2_key[0].public_key_openssh : file(var.bastion_existing_pem)
}

resource "aws_secretsmanager_secret" "bastion_private_key" {
  count       = var.enable_bastion && var.bastion_existing_pem == "" ? 1 : 0
  name        = "${var.bastion_key_name}-private-key"
  description = "Private key for bastion host SSH access"
}

resource "aws_secretsmanager_secret_version" "bastion_private_key_value" {
  count         = var.enable_bastion && var.bastion_existing_pem == "" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.bastion_private_key[0].id
  secret_string = tls_private_key.bastion_ec2_key[0].private_key_pem
}


# EC2 Instance for Bastion
resource "aws_instance" "bastion_ec2" {
  count                       = var.enable_bastion ? 1 : 0
  ami                         = var.bastion_ami
  instance_type               = var.bastion_instance_type
  subnet_id                   = var.bastion_public_subnet_id
  vpc_security_group_ids      = [aws_security_group.bastion_ec2_sg[0].id]
  key_name                    = var.bastion_key_name
  associate_public_ip_address = true
  iam_instance_profile        = var.bastion_profile_name

  root_block_device {
    volume_size           = var.bastion_disk_size
    volume_type           = "gp2"
    delete_on_termination = true
    encrypted             = true
  }
  tags = merge(
    var.tags,
    {
      Name = var.bastion_ec2_name
    }
  )
}

resource "aws_eks_access_entry" "bastion_access" {
  count         = var.enable_bastion ? 1 : 0
  cluster_name  = module.eks.cluster_name
  principal_arn = var.bastion_eks_admin_role_arn
  type          = "STANDARD"

  tags = {
    Name = "bastion-admin-access"
  }
}

resource "aws_eks_access_policy_association" "bastion_access" {
  count         = var.enable_bastion ? 1 : 0
  cluster_name  = module.eks.cluster_name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = var.bastion_eks_admin_role_arn

  access_scope {
    type = "cluster"
  }
}



