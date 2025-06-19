

# Security Group for EC2
resource "aws_security_group" "ec2_sg" {
  count       = var.enable_nfs ? 1 : 0
  name        = var.security_group_name
  description = var.nfs_security_group_description
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.nfs_ingress_rules
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
resource "tls_private_key" "ec2_key" {
  count     = var.enable_nfs && var.existing_pem == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Key Pair
resource "aws_key_pair" "ec2_key" {
  count      = var.enable_nfs ? 1 : 0
  key_name   = var.key_name
  public_key = var.existing_pem == "" ? tls_private_key.ec2_key[0].public_key_openssh : file(var.existing_pem)
}

# EC2 Instance for NFS
resource "aws_instance" "nfs_ec2" {
  count                       = var.enable_nfs ? 1 : 0
  ami                         = var.ami
  instance_type               = var.instance_type
  subnet_id                   = var.nfs_private_subnet_id
  vpc_security_group_ids      = [aws_security_group.ec2_sg[0].id]
  key_name                    = var.key_name
  associate_public_ip_address = false

  root_block_device {
    volume_size           = var.disk_size
    volume_type           = "gp2"
    delete_on_termination = true
    encrypted             = true
  }
  tags = merge(
    var.tags,
    {
      Name = var.ec2_name
    }
  )
}
