# Define the security group for OpenSearch
resource "aws_security_group" "opensearch_sg" {
  count       = var.enable_opensearch ? 1 : 0
  name        = var.opensearch_security_group_name
  description = var.opensearch_security_group_description
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.opensearch_ingress_rules
    content {
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

data "aws_caller_identity" "current" {}


# Local to determine if override_main_response_version is supported
# This option is NOT supported in OpenSearch 2.x, but IS supported in 1.x, 3.x+, and Elasticsearch
locals {
  opensearch_major_version = (
    startswith(var.engine_version, "OpenSearch_") ?
    tonumber(split(".", split("_", var.engine_version)[1])[0]) :
    0 # Elasticsearch versions
  )

  # Exclude override_main_response_version only for OpenSearch 2.x
  supports_override_response_version = local.opensearch_major_version != 2

  advanced_options_base = {
    "indices.fielddata.cache.size"           = "20"
    "indices.query.bool.max_clause_count"    = "1024"
    "rest.action.multi.allow_explicit_index" = "true"
  }

  advanced_options = local.supports_override_response_version ? merge(local.advanced_options_base, {
    "override_main_response_version" = "false"
  }) : local.advanced_options_base
}

# OpenSearch module configuration
module "opensearch" {
  count                 = var.enable_opensearch ? 1 : 0
  source                = "terraform-aws-modules/opensearch/aws"
  version               = "1.7.0"
  create_security_group = false

  # Domain
  advanced_options = local.advanced_options

  advanced_security_options = {
    enabled                        = true
    anonymous_auth_enabled         = false
    internal_user_database_enabled = true

    master_user_options = {
      master_user_name     = var.master_user_name
      master_user_password = jsondecode(data.aws_secretsmanager_secret_version.opensearch[0].secret_string).password
    }
  }

  cluster_config = {
    instance_count           = var.number_of_nodes
    dedicated_master_enabled = var.enable_masternodes
    instance_type            = var.opensearch_instance_type

    dedicated_master_count = var.enable_masternodes ? var.number_of_master_nodes : 0
    dedicated_master_type  = var.enable_masternodes ? var.opensearch_instance_type : ""

    zone_awareness_config = {
      availability_zone_count = var.zone_awareness_enabled ? var.availability_zone_count : 1
    }
    zone_awareness_enabled = var.zone_awareness_enabled
  }

  domain_endpoint_options = {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  domain_name = var.domain_name

  ebs_options = {
    ebs_enabled = true
    volume_type = var.ebs_volume_type
    volume_size = var.ebs_volume_size
  }
  encrypt_at_rest = {
    enabled = true
  }
  engine_version = var.engine_version

  log_publishing_options = var.opensearch_log_publishing_options
  node_to_node_encryption = {
    enabled = true
  }
  vpc_options = {
    security_group_ids = [aws_security_group.opensearch_sg[0].id]
    subnet_ids         = var.opensearch_subnet_ids
  }
  software_update_options = {
    auto_software_update_enabled = var.auto_software_update_enabled
  }
  enable_access_policy = true
  create_access_policy = false # Because we're supplying access_policies directly

  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action   = "es:*"
        Resource = "arn:aws:es:${var.region}:${data.aws_caller_identity.current.account_id}:domain/${var.domain_name}/*"
      }
    ]
  })

  tags = var.tags
}
