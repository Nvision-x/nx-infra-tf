################################################################################
# CloudWatch monitoring for production
#
# One SNS topic fans every alarm out to (a) email subscribers and (b) Amazon Q
# Developer in chat applications (formerly AWS Chatbot) -> Slack. Alarms cover
# every stateful / operationally-critical resource this module creates: EKS,
# RDS, OpenSearch, Neptune, the bastion/NFS EC2 hosts, and EFS.
#
# Everything is gated on var.enable_monitoring plus the per-category flag plus
# the resource's own enable flag. Thresholds/periods are all variables — see
# variables-monitoring.tf.
################################################################################

locals {
  # Master gate composed with each category flag and the resource's own switch.
  mon_eks       = var.enable_monitoring && var.monitoring_eks_enabled
  mon_rds       = var.enable_monitoring && var.monitoring_rds_enabled && var.enable_postgres
  mon_os        = var.enable_monitoring && var.monitoring_opensearch_enabled && var.enable_opensearch
  mon_os_master = var.enable_monitoring && var.monitoring_opensearch_enabled && var.enable_opensearch && var.enable_masternodes
  mon_neptune   = var.enable_monitoring && var.monitoring_neptune_enabled && var.enable_neptune
  mon_bastion   = var.enable_monitoring && var.monitoring_ec2_enabled && var.enable_bastion
  mon_nfs       = var.enable_monitoring && var.monitoring_ec2_enabled && var.enable_nfs
  mon_efs       = var.enable_monitoring && var.monitoring_efs_enabled && var.enable_efs

  monitoring_account_id = data.aws_caller_identity.current.account_id
  monitoring_name       = var.monitoring_alarm_name_prefix != "" ? var.monitoring_alarm_name_prefix : var.cluster_name

  # Resolve the alarm target topic: caller-supplied wins, otherwise the one we create.
  monitoring_create_sns = var.enable_monitoring && var.monitoring_sns_topic_arn == ""
  monitoring_sns_arn = var.monitoring_sns_topic_arn != "" ? var.monitoring_sns_topic_arn : (
    local.monitoring_create_sns ? aws_sns_topic.monitoring[0].arn : null
  )

  monitoring_alarm_actions = compact(concat(
    [local.monitoring_sns_arn == null ? "" : local.monitoring_sns_arn],
    var.monitoring_additional_alarm_action_arns
  ))
  monitoring_ok_actions = var.monitoring_notify_on_ok ? local.monitoring_alarm_actions : []

  # Plan-time-known gate for the Amazon Q / Chatbot Slack config. Must NOT
  # reference monitoring_sns_arn: when the topic is created in the same apply
  # its ARN is unknown at plan time, which would make count indeterminate.
  # When monitoring is enabled a topic always exists (created or caller-supplied).
  monitoring_slack_enabled = var.enable_monitoring && var.monitoring_slack_workspace_id != "" && var.monitoring_slack_channel_id != ""

  # Encrypt the topic we create (Security Hub SNS.1). Use a caller-supplied key
  # if given, otherwise a customer-managed CMK created here. A CMK (not the
  # AWS-managed alias/aws/sns) is required so the key policy can grant
  # CloudWatch permission to publish to the encrypted topic.
  monitoring_create_kms = local.monitoring_create_sns && var.monitoring_kms_key_id == ""
  monitoring_kms_key_id = var.monitoring_kms_key_id != "" ? var.monitoring_kms_key_id : (
    local.monitoring_create_kms ? aws_kms_key.monitoring[0].id : null
  )

  # Expected reachable OpenSearch node count (data + master + coordinator) unless overridden.
  os_expected_nodes = var.opensearch_min_nodes_threshold > 0 ? var.opensearch_min_nodes_threshold : (
    var.number_of_nodes
    + (var.enable_masternodes ? var.number_of_master_nodes : 0)
    + (var.opensearch_coordinator_nodes_enabled ? var.opensearch_coordinator_node_count : 0)
  )

  # Neptune serverless: alarm when capacity (ACUs) reaches a % of the configured max.
  neptune_capacity_threshold = var.neptune_max_ncu * var.neptune_capacity_utilization_threshold / 100
}

################################################################################
# SNS topic + subscriptions
################################################################################

# Customer-managed KMS key encrypting the alarm topic (Security Hub SNS.1).
# Rotation on (KMS.4). Policy grants the account plus CloudWatch (so alarms can
# publish to the encrypted topic — the AWS-managed SNS key can't be granted this).
resource "aws_kms_key" "monitoring" {
  count                   = local.monitoring_create_kms ? 1 : 0
  description             = "Encrypts the ${local.monitoring_name} CloudWatch alarm SNS topic"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootPermissions"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.monitoring_account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowCloudWatchAlarmsUseOfKey"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = ["kms:GenerateDataKey*", "kms:Decrypt"]
        Resource  = "*"
      }
    ]
  })

  tags = var.tags
}

resource "aws_kms_alias" "monitoring" {
  count         = local.monitoring_create_kms ? 1 : 0
  name          = "alias/${local.monitoring_name}-monitoring-alarms"
  target_key_id = aws_kms_key.monitoring[0].key_id
}

resource "aws_sns_topic" "monitoring" {
  count             = local.monitoring_create_sns ? 1 : 0
  name              = "${local.monitoring_name}-cloudwatch-alarms"
  kms_master_key_id = local.monitoring_kms_key_id
  tags              = var.tags
}

# Allow CloudWatch alarms to publish (scoped to this account) and deny non-TLS.
data "aws_iam_policy_document" "monitoring_sns" {
  count = local.monitoring_create_sns ? 1 : 0

  statement {
    sid       = "AllowCloudWatchAlarmsPublish"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.monitoring[0].arn]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.monitoring_account_id]
    }
  }

  statement {
    sid       = "DenyNonTLS"
    effect    = "Deny"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.monitoring[0].arn]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sns_topic_policy" "monitoring" {
  count  = local.monitoring_create_sns ? 1 : 0
  arn    = aws_sns_topic.monitoring[0].arn
  policy = data.aws_iam_policy_document.monitoring_sns[0].json
}

resource "aws_sns_topic_subscription" "monitoring_email" {
  for_each  = local.monitoring_create_sns ? toset(var.monitoring_alarm_emails) : toset([])
  topic_arn = aws_sns_topic.monitoring[0].arn
  protocol  = "email"
  endpoint  = each.value
}

################################################################################
# Amazon Q Developer in chat applications (AWS Chatbot) -> Slack
#
# Requires a one-time manual authorization of the Slack workspace in the
# Amazon Q / AWS Chatbot console. Skipped until both Slack IDs are supplied.
################################################################################

data "aws_iam_policy_document" "monitoring_chatbot_assume" {
  count = local.monitoring_slack_enabled ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["chatbot.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "monitoring_chatbot" {
  count              = local.monitoring_slack_enabled ? 1 : 0
  name               = "${local.monitoring_name}-chatbot-alarms"
  assume_role_policy = data.aws_iam_policy_document.monitoring_chatbot_assume[0].json
  tags               = var.tags
}

# Notifications-only: read-only visibility, no mutating actions from chat.
resource "aws_iam_role_policy_attachment" "monitoring_chatbot_readonly" {
  count      = local.monitoring_slack_enabled ? 1 : 0
  role       = aws_iam_role.monitoring_chatbot[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

resource "aws_chatbot_slack_channel_configuration" "monitoring" {
  count = local.monitoring_slack_enabled ? 1 : 0

  configuration_name    = "${local.monitoring_name}-alarms"
  iam_role_arn          = aws_iam_role.monitoring_chatbot[0].arn
  slack_team_id         = var.monitoring_slack_workspace_id
  slack_channel_id      = var.monitoring_slack_channel_id
  sns_topic_arns        = [local.monitoring_sns_arn]
  guardrail_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
  logging_level         = "ERROR"
  tags                  = var.tags
}

################################################################################
# EKS / Container Insights
# Metrics come from the amazon-cloudwatch-observability addon installed in
# eks-cluster.tf. Cluster-wide worst-node view via Maximum over ClusterName.
################################################################################

resource "aws_cloudwatch_metric_alarm" "eks_node_cpu" {
  count               = local.mon_eks ? 1 : 0
  alarm_name          = "${local.monitoring_name}-eks-node-cpu-high"
  alarm_description   = "An EKS node's CPU utilization is above ${var.eks_node_cpu_threshold}%"
  namespace           = "ContainerInsights"
  metric_name         = "node_cpu_utilization"
  dimensions          = { ClusterName = module.eks.cluster_name }
  statistic           = "Maximum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.eks_node_cpu_threshold
  period              = var.monitoring_alarm_period
  evaluation_periods  = var.monitoring_alarm_evaluation_periods
  datapoints_to_alarm = var.monitoring_datapoints_to_alarm
  treat_missing_data  = var.monitoring_treat_missing_data
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "eks_node_memory" {
  count               = local.mon_eks ? 1 : 0
  alarm_name          = "${local.monitoring_name}-eks-node-memory-high"
  alarm_description   = "An EKS node's memory utilization is above ${var.eks_node_memory_threshold}%"
  namespace           = "ContainerInsights"
  metric_name         = "node_memory_utilization"
  dimensions          = { ClusterName = module.eks.cluster_name }
  statistic           = "Maximum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.eks_node_memory_threshold
  period              = var.monitoring_alarm_period
  evaluation_periods  = var.monitoring_alarm_evaluation_periods
  datapoints_to_alarm = var.monitoring_datapoints_to_alarm
  treat_missing_data  = var.monitoring_treat_missing_data
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "eks_node_filesystem" {
  count               = local.mon_eks ? 1 : 0
  alarm_name          = "${local.monitoring_name}-eks-node-disk-high"
  alarm_description   = "An EKS node's filesystem utilization is above ${var.eks_node_filesystem_threshold}%"
  namespace           = "ContainerInsights"
  metric_name         = "node_filesystem_utilization"
  dimensions          = { ClusterName = module.eks.cluster_name }
  statistic           = "Maximum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.eks_node_filesystem_threshold
  period              = var.monitoring_alarm_period
  evaluation_periods  = var.monitoring_alarm_evaluation_periods
  datapoints_to_alarm = var.monitoring_datapoints_to_alarm
  treat_missing_data  = var.monitoring_treat_missing_data
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "eks_failed_nodes" {
  count               = local.mon_eks ? 1 : 0
  alarm_name          = "${local.monitoring_name}-eks-failed-nodes"
  alarm_description   = "One or more EKS nodes are in a failed/NotReady state"
  namespace           = "ContainerInsights"
  metric_name         = "cluster_failed_node_count"
  dimensions          = { ClusterName = module.eks.cluster_name }
  statistic           = "Maximum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  period              = var.monitoring_alarm_period
  evaluation_periods  = var.monitoring_alarm_evaluation_periods
  datapoints_to_alarm = var.monitoring_datapoints_to_alarm
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

################################################################################
# RDS PostgreSQL
################################################################################

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  count               = local.mon_rds ? 1 : 0
  alarm_name          = "${local.monitoring_name}-rds-cpu-high"
  alarm_description   = "RDS ${var.db_identifier} CPU utilization is above ${var.rds_cpu_threshold}%"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBInstanceIdentifier = var.db_identifier }
  statistic           = "Average"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.rds_cpu_threshold
  period              = var.monitoring_alarm_period
  evaluation_periods  = var.monitoring_alarm_evaluation_periods
  datapoints_to_alarm = var.monitoring_datapoints_to_alarm
  treat_missing_data  = var.monitoring_treat_missing_data
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "rds_freeable_memory" {
  count               = local.mon_rds ? 1 : 0
  alarm_name          = "${local.monitoring_name}-rds-freeable-memory-low"
  alarm_description   = "RDS ${var.db_identifier} freeable memory is below ${var.rds_freeable_memory_bytes_threshold} bytes"
  namespace           = "AWS/RDS"
  metric_name         = "FreeableMemory"
  dimensions          = { DBInstanceIdentifier = var.db_identifier }
  statistic           = "Average"
  comparison_operator = "LessThanThreshold"
  threshold           = var.rds_freeable_memory_bytes_threshold
  period              = var.monitoring_alarm_period
  evaluation_periods  = var.monitoring_alarm_evaluation_periods
  datapoints_to_alarm = var.monitoring_datapoints_to_alarm
  treat_missing_data  = var.monitoring_treat_missing_data
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "rds_free_storage" {
  count               = local.mon_rds ? 1 : 0
  alarm_name          = "${local.monitoring_name}-rds-free-storage-low"
  alarm_description   = "RDS ${var.db_identifier} free storage is below ${var.rds_free_storage_bytes_threshold} bytes"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  dimensions          = { DBInstanceIdentifier = var.db_identifier }
  statistic           = "Average"
  comparison_operator = "LessThanThreshold"
  threshold           = var.rds_free_storage_bytes_threshold
  period              = var.monitoring_alarm_period
  evaluation_periods  = var.monitoring_alarm_evaluation_periods
  datapoints_to_alarm = var.monitoring_datapoints_to_alarm
  treat_missing_data  = var.monitoring_treat_missing_data
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  count               = local.mon_rds ? 1 : 0
  alarm_name          = "${local.monitoring_name}-rds-connections-high"
  alarm_description   = "RDS ${var.db_identifier} database connections are above ${var.rds_connections_threshold}"
  namespace           = "AWS/RDS"
  metric_name         = "DatabaseConnections"
  dimensions          = { DBInstanceIdentifier = var.db_identifier }
  statistic           = "Average"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.rds_connections_threshold
  period              = var.monitoring_alarm_period
  evaluation_periods  = var.monitoring_alarm_evaluation_periods
  datapoints_to_alarm = var.monitoring_datapoints_to_alarm
  treat_missing_data  = var.monitoring_treat_missing_data
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "rds_read_latency" {
  count               = local.mon_rds ? 1 : 0
  alarm_name          = "${local.monitoring_name}-rds-read-latency-high"
  alarm_description   = "RDS ${var.db_identifier} read latency is above ${var.rds_read_latency_threshold}s"
  namespace           = "AWS/RDS"
  metric_name         = "ReadLatency"
  dimensions          = { DBInstanceIdentifier = var.db_identifier }
  statistic           = "Average"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.rds_read_latency_threshold
  period              = var.monitoring_alarm_period
  evaluation_periods  = var.monitoring_alarm_evaluation_periods
  datapoints_to_alarm = var.monitoring_datapoints_to_alarm
  treat_missing_data  = var.monitoring_treat_missing_data
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "rds_write_latency" {
  count               = local.mon_rds ? 1 : 0
  alarm_name          = "${local.monitoring_name}-rds-write-latency-high"
  alarm_description   = "RDS ${var.db_identifier} write latency is above ${var.rds_write_latency_threshold}s"
  namespace           = "AWS/RDS"
  metric_name         = "WriteLatency"
  dimensions          = { DBInstanceIdentifier = var.db_identifier }
  statistic           = "Average"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.rds_write_latency_threshold
  period              = var.monitoring_alarm_period
  evaluation_periods  = var.monitoring_alarm_evaluation_periods
  datapoints_to_alarm = var.monitoring_datapoints_to_alarm
  treat_missing_data  = var.monitoring_treat_missing_data
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "rds_disk_queue_depth" {
  count               = local.mon_rds ? 1 : 0
  alarm_name          = "${local.monitoring_name}-rds-disk-queue-depth-high"
  alarm_description   = "RDS ${var.db_identifier} disk queue depth is above ${var.rds_disk_queue_depth_threshold}"
  namespace           = "AWS/RDS"
  metric_name         = "DiskQueueDepth"
  dimensions          = { DBInstanceIdentifier = var.db_identifier }
  statistic           = "Average"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.rds_disk_queue_depth_threshold
  period              = var.monitoring_alarm_period
  evaluation_periods  = var.monitoring_alarm_evaluation_periods
  datapoints_to_alarm = var.monitoring_datapoints_to_alarm
  treat_missing_data  = var.monitoring_treat_missing_data
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "rds_swap_usage" {
  count               = local.mon_rds ? 1 : 0
  alarm_name          = "${local.monitoring_name}-rds-swap-usage-high"
  alarm_description   = "RDS ${var.db_identifier} swap usage is above ${var.rds_swap_usage_bytes_threshold} bytes"
  namespace           = "AWS/RDS"
  metric_name         = "SwapUsage"
  dimensions          = { DBInstanceIdentifier = var.db_identifier }
  statistic           = "Average"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.rds_swap_usage_bytes_threshold
  period              = var.monitoring_alarm_period
  evaluation_periods  = var.monitoring_alarm_evaluation_periods
  datapoints_to_alarm = var.monitoring_datapoints_to_alarm
  treat_missing_data  = var.monitoring_treat_missing_data
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

################################################################################
# OpenSearch  (dimensions: DomainName + ClientId)
################################################################################

resource "aws_cloudwatch_metric_alarm" "opensearch_cluster_red" {
  count               = local.mon_os ? 1 : 0
  alarm_name          = "${local.monitoring_name}-opensearch-status-red"
  alarm_description   = "OpenSearch ${var.domain_name} cluster status is RED (primary shards unassigned)"
  namespace           = "AWS/ES"
  metric_name         = "ClusterStatus.red"
  dimensions          = { DomainName = var.domain_name, ClientId = local.monitoring_account_id }
  statistic           = "Maximum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  period              = var.monitoring_alarm_period
  evaluation_periods  = var.monitoring_alarm_evaluation_periods
  datapoints_to_alarm = var.monitoring_datapoints_to_alarm
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "opensearch_cluster_yellow" {
  count               = local.mon_os ? 1 : 0
  alarm_name          = "${local.monitoring_name}-opensearch-status-yellow"
  alarm_description   = "OpenSearch ${var.domain_name} cluster status is YELLOW (replica shards unassigned)"
  namespace           = "AWS/ES"
  metric_name         = "ClusterStatus.yellow"
  dimensions          = { DomainName = var.domain_name, ClientId = local.monitoring_account_id }
  statistic           = "Maximum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  period              = var.monitoring_alarm_period
  evaluation_periods  = var.monitoring_alarm_evaluation_periods
  datapoints_to_alarm = var.monitoring_datapoints_to_alarm
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "opensearch_free_storage" {
  count               = local.mon_os ? 1 : 0
  alarm_name          = "${local.monitoring_name}-opensearch-free-storage-low"
  alarm_description   = "OpenSearch ${var.domain_name} per-node free storage is below ${var.opensearch_free_storage_mb_threshold} MB (writes are blocked near 1 GB)"
  namespace           = "AWS/ES"
  metric_name         = "FreeStorageSpace"
  dimensions          = { DomainName = var.domain_name, ClientId = local.monitoring_account_id }
  statistic           = "Minimum"
  comparison_operator = "LessThanThreshold"
  threshold           = var.opensearch_free_storage_mb_threshold
  period              = var.monitoring_alarm_period
  evaluation_periods  = var.monitoring_alarm_evaluation_periods
  datapoints_to_alarm = var.monitoring_datapoints_to_alarm
  treat_missing_data  = var.monitoring_treat_missing_data
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "opensearch_cpu" {
  count               = local.mon_os ? 1 : 0
  alarm_name          = "${local.monitoring_name}-opensearch-cpu-high"
  alarm_description   = "OpenSearch ${var.domain_name} data-node CPU utilization is above ${var.opensearch_cpu_threshold}%"
  namespace           = "AWS/ES"
  metric_name         = "CPUUtilization"
  dimensions          = { DomainName = var.domain_name, ClientId = local.monitoring_account_id }
  statistic           = "Average"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.opensearch_cpu_threshold
  period              = var.monitoring_alarm_period
  evaluation_periods  = var.monitoring_alarm_evaluation_periods
  datapoints_to_alarm = var.monitoring_datapoints_to_alarm
  treat_missing_data  = var.monitoring_treat_missing_data
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "opensearch_jvm_pressure" {
  count               = local.mon_os ? 1 : 0
  alarm_name          = "${local.monitoring_name}-opensearch-jvm-pressure-high"
  alarm_description   = "OpenSearch ${var.domain_name} JVM memory pressure is above ${var.opensearch_jvm_pressure_threshold}%"
  namespace           = "AWS/ES"
  metric_name         = "JVMMemoryPressure"
  dimensions          = { DomainName = var.domain_name, ClientId = local.monitoring_account_id }
  statistic           = "Maximum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.opensearch_jvm_pressure_threshold
  period              = var.monitoring_alarm_period
  evaluation_periods  = var.monitoring_alarm_evaluation_periods
  datapoints_to_alarm = var.monitoring_datapoints_to_alarm
  treat_missing_data  = var.monitoring_treat_missing_data
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "opensearch_old_gen_jvm_pressure" {
  count               = local.mon_os ? 1 : 0
  alarm_name          = "${local.monitoring_name}-opensearch-oldgen-jvm-pressure-high"
  alarm_description   = "OpenSearch ${var.domain_name} old-gen JVM memory pressure is above ${var.opensearch_old_gen_jvm_pressure_threshold}%"
  namespace           = "AWS/ES"
  metric_name         = "OldGenJVMMemoryPressure"
  dimensions          = { DomainName = var.domain_name, ClientId = local.monitoring_account_id }
  statistic           = "Maximum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.opensearch_old_gen_jvm_pressure_threshold
  period              = var.monitoring_alarm_period
  evaluation_periods  = var.monitoring_alarm_evaluation_periods
  datapoints_to_alarm = var.monitoring_datapoints_to_alarm
  treat_missing_data  = var.monitoring_treat_missing_data
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "opensearch_writes_blocked" {
  count               = local.mon_os ? 1 : 0
  alarm_name          = "${local.monitoring_name}-opensearch-writes-blocked"
  alarm_description   = "OpenSearch ${var.domain_name} is blocking index writes (disk/JVM watermark)"
  namespace           = "AWS/ES"
  metric_name         = "ClusterIndexWritesBlocked"
  dimensions          = { DomainName = var.domain_name, ClientId = local.monitoring_account_id }
  statistic           = "Maximum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  period              = var.monitoring_alarm_period
  evaluation_periods  = var.monitoring_alarm_evaluation_periods
  datapoints_to_alarm = var.monitoring_datapoints_to_alarm
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "opensearch_nodes" {
  count               = local.mon_os ? 1 : 0
  alarm_name          = "${local.monitoring_name}-opensearch-nodes-low"
  alarm_description   = "OpenSearch ${var.domain_name} reachable node count is below the expected ${local.os_expected_nodes}"
  namespace           = "AWS/ES"
  metric_name         = "Nodes"
  dimensions          = { DomainName = var.domain_name, ClientId = local.monitoring_account_id }
  statistic           = "Minimum"
  comparison_operator = "LessThanThreshold"
  threshold           = local.os_expected_nodes
  period              = var.monitoring_alarm_period
  evaluation_periods  = var.monitoring_alarm_evaluation_periods
  datapoints_to_alarm = var.monitoring_datapoints_to_alarm
  treat_missing_data  = var.monitoring_treat_missing_data
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "opensearch_snapshot_failure" {
  count               = local.mon_os ? 1 : 0
  alarm_name          = "${local.monitoring_name}-opensearch-snapshot-failure"
  alarm_description   = "OpenSearch ${var.domain_name} automated snapshot failed"
  namespace           = "AWS/ES"
  metric_name         = "AutomatedSnapshotFailure"
  dimensions          = { DomainName = var.domain_name, ClientId = local.monitoring_account_id }
  statistic           = "Maximum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  period              = var.monitoring_alarm_period
  evaluation_periods  = var.monitoring_alarm_evaluation_periods
  datapoints_to_alarm = var.monitoring_datapoints_to_alarm
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "opensearch_kms_error" {
  count               = local.mon_os ? 1 : 0
  alarm_name          = "${local.monitoring_name}-opensearch-kms-error"
  alarm_description   = "OpenSearch ${var.domain_name} cannot access its KMS encryption key"
  namespace           = "AWS/ES"
  metric_name         = "KMSKeyError"
  dimensions          = { DomainName = var.domain_name, ClientId = local.monitoring_account_id }
  statistic           = "Maximum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  period              = var.monitoring_alarm_period
  evaluation_periods  = var.monitoring_alarm_evaluation_periods
  datapoints_to_alarm = var.monitoring_datapoints_to_alarm
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "opensearch_5xx" {
  count               = local.mon_os ? 1 : 0
  alarm_name          = "${local.monitoring_name}-opensearch-5xx-high"
  alarm_description   = "OpenSearch ${var.domain_name} 5xx responses exceed ${var.opensearch_5xx_threshold} per period"
  namespace           = "AWS/ES"
  metric_name         = "5xx"
  dimensions          = { DomainName = var.domain_name, ClientId = local.monitoring_account_id }
  statistic           = "Sum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.opensearch_5xx_threshold
  period              = var.monitoring_alarm_period
  evaluation_periods  = var.monitoring_alarm_evaluation_periods
  datapoints_to_alarm = var.monitoring_datapoints_to_alarm
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "opensearch_master_reachable" {
  count               = local.mon_os_master ? 1 : 0
  alarm_name          = "${local.monitoring_name}-opensearch-master-unreachable"
  alarm_description   = "OpenSearch ${var.domain_name} dedicated master is not reachable from data nodes"
  namespace           = "AWS/ES"
  metric_name         = "MasterReachableFromNode"
  dimensions          = { DomainName = var.domain_name, ClientId = local.monitoring_account_id }
  statistic           = "Minimum"
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  period              = var.monitoring_alarm_period
  evaluation_periods  = var.monitoring_alarm_evaluation_periods
  datapoints_to_alarm = var.monitoring_datapoints_to_alarm
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "opensearch_master_cpu" {
  count               = local.mon_os_master ? 1 : 0
  alarm_name          = "${local.monitoring_name}-opensearch-master-cpu-high"
  alarm_description   = "OpenSearch ${var.domain_name} dedicated master CPU utilization is above ${var.opensearch_master_cpu_threshold}%"
  namespace           = "AWS/ES"
  metric_name         = "MasterCPUUtilization"
  dimensions          = { DomainName = var.domain_name, ClientId = local.monitoring_account_id }
  statistic           = "Average"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.opensearch_master_cpu_threshold
  period              = var.monitoring_alarm_period
  evaluation_periods  = var.monitoring_alarm_evaluation_periods
  datapoints_to_alarm = var.monitoring_datapoints_to_alarm
  treat_missing_data  = var.monitoring_treat_missing_data
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "opensearch_master_jvm_pressure" {
  count               = local.mon_os_master ? 1 : 0
  alarm_name          = "${local.monitoring_name}-opensearch-master-jvm-pressure-high"
  alarm_description   = "OpenSearch ${var.domain_name} dedicated master JVM memory pressure is above ${var.opensearch_master_jvm_pressure_threshold}%"
  namespace           = "AWS/ES"
  metric_name         = "MasterJVMMemoryPressure"
  dimensions          = { DomainName = var.domain_name, ClientId = local.monitoring_account_id }
  statistic           = "Maximum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.opensearch_master_jvm_pressure_threshold
  period              = var.monitoring_alarm_period
  evaluation_periods  = var.monitoring_alarm_evaluation_periods
  datapoints_to_alarm = var.monitoring_datapoints_to_alarm
  treat_missing_data  = var.monitoring_treat_missing_data
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

################################################################################
# Neptune  (serverless)
################################################################################

resource "aws_cloudwatch_metric_alarm" "neptune_cpu" {
  count               = local.mon_neptune ? 1 : 0
  alarm_name          = "${local.monitoring_name}-neptune-cpu-high"
  alarm_description   = "Neptune ${var.neptune_cluster_identifier} CPU utilization is above ${var.neptune_cpu_threshold}%"
  namespace           = "AWS/Neptune"
  metric_name         = "CPUUtilization"
  dimensions          = { DBClusterIdentifier = var.neptune_cluster_identifier }
  statistic           = "Average"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.neptune_cpu_threshold
  period              = var.monitoring_alarm_period
  evaluation_periods  = var.monitoring_alarm_evaluation_periods
  datapoints_to_alarm = var.monitoring_datapoints_to_alarm
  treat_missing_data  = var.monitoring_treat_missing_data
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "neptune_capacity" {
  count               = local.mon_neptune ? 1 : 0
  alarm_name          = "${local.monitoring_name}-neptune-capacity-high"
  alarm_description   = "Neptune ${var.neptune_cluster_identifier} serverless capacity is at/above ${var.neptune_capacity_utilization_threshold}% of the ${var.neptune_max_ncu} NCU ceiling"
  namespace           = "AWS/Neptune"
  metric_name         = "ServerlessDatabaseCapacity"
  dimensions          = { DBClusterIdentifier = var.neptune_cluster_identifier }
  statistic           = "Average"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = local.neptune_capacity_threshold
  period              = var.monitoring_alarm_period
  evaluation_periods  = var.monitoring_alarm_evaluation_periods
  datapoints_to_alarm = var.monitoring_datapoints_to_alarm
  treat_missing_data  = var.monitoring_treat_missing_data
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "neptune_pending_requests" {
  count               = local.mon_neptune ? 1 : 0
  alarm_name          = "${local.monitoring_name}-neptune-pending-requests-high"
  alarm_description   = "Neptune ${var.neptune_cluster_identifier} main request queue backlog is above ${var.neptune_main_queue_pending_threshold}"
  namespace           = "AWS/Neptune"
  metric_name         = "MainRequestQueuePendingRequests"
  dimensions          = { DBClusterIdentifier = var.neptune_cluster_identifier }
  statistic           = "Average"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.neptune_main_queue_pending_threshold
  period              = var.monitoring_alarm_period
  evaluation_periods  = var.monitoring_alarm_evaluation_periods
  datapoints_to_alarm = var.monitoring_datapoints_to_alarm
  treat_missing_data  = var.monitoring_treat_missing_data
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

################################################################################
# EC2 — bastion & NFS
################################################################################

resource "aws_cloudwatch_metric_alarm" "bastion_status_check" {
  count               = local.mon_bastion ? 1 : 0
  alarm_name          = "${local.monitoring_name}-bastion-status-check-failed"
  alarm_description   = "Bastion EC2 instance failed an EC2/system status check"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  dimensions          = { InstanceId = aws_instance.bastion_ec2[0].id }
  statistic           = "Maximum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  period              = var.monitoring_alarm_period
  evaluation_periods  = var.monitoring_alarm_evaluation_periods
  datapoints_to_alarm = var.monitoring_datapoints_to_alarm
  treat_missing_data  = "breaching"
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "bastion_cpu" {
  count               = local.mon_bastion ? 1 : 0
  alarm_name          = "${local.monitoring_name}-bastion-cpu-high"
  alarm_description   = "Bastion EC2 CPU utilization is above ${var.ec2_cpu_threshold}%"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { InstanceId = aws_instance.bastion_ec2[0].id }
  statistic           = "Average"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.ec2_cpu_threshold
  period              = var.monitoring_alarm_period
  evaluation_periods  = var.monitoring_alarm_evaluation_periods
  datapoints_to_alarm = var.monitoring_datapoints_to_alarm
  treat_missing_data  = var.monitoring_treat_missing_data
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "nfs_status_check" {
  count               = local.mon_nfs ? 1 : 0
  alarm_name          = "${local.monitoring_name}-nfs-status-check-failed"
  alarm_description   = "NFS EC2 instance failed an EC2/system status check"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  dimensions          = { InstanceId = aws_instance.nfs_ec2[0].id }
  statistic           = "Maximum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  period              = var.monitoring_alarm_period
  evaluation_periods  = var.monitoring_alarm_evaluation_periods
  datapoints_to_alarm = var.monitoring_datapoints_to_alarm
  treat_missing_data  = "breaching"
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "nfs_cpu" {
  count               = local.mon_nfs ? 1 : 0
  alarm_name          = "${local.monitoring_name}-nfs-cpu-high"
  alarm_description   = "NFS EC2 CPU utilization is above ${var.ec2_cpu_threshold}%"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { InstanceId = aws_instance.nfs_ec2[0].id }
  statistic           = "Average"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.ec2_cpu_threshold
  period              = var.monitoring_alarm_period
  evaluation_periods  = var.monitoring_alarm_evaluation_periods
  datapoints_to_alarm = var.monitoring_datapoints_to_alarm
  treat_missing_data  = var.monitoring_treat_missing_data
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

################################################################################
# EFS
################################################################################

resource "aws_cloudwatch_metric_alarm" "efs_percent_io_limit" {
  count               = local.mon_efs ? 1 : 0
  alarm_name          = "${local.monitoring_name}-efs-percent-io-limit-high"
  alarm_description   = "EFS ${var.cluster_name}-efs is approaching its IOPS limit (PercentIOLimit above ${var.efs_percent_io_limit_threshold}%)"
  namespace           = "AWS/EFS"
  metric_name         = "PercentIOLimit"
  dimensions          = { FileSystemId = aws_efs_file_system.this[0].id }
  statistic           = "Maximum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.efs_percent_io_limit_threshold
  period              = var.monitoring_alarm_period
  evaluation_periods  = var.monitoring_alarm_evaluation_periods
  datapoints_to_alarm = var.monitoring_datapoints_to_alarm
  treat_missing_data  = var.monitoring_treat_missing_data
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

################################################################################
# Dashboard — single pane across everything that is monitored
################################################################################

locals {
  dashboard_widget_specs = concat(
    local.mon_eks ? [
      {
        title = "EKS — Node utilization (%)"
        stat  = "Maximum"
        metrics = [
          ["ContainerInsights", "node_cpu_utilization", "ClusterName", module.eks.cluster_name],
          ["ContainerInsights", "node_memory_utilization", "ClusterName", module.eks.cluster_name],
          ["ContainerInsights", "node_filesystem_utilization", "ClusterName", module.eks.cluster_name],
        ]
      },
      {
        title = "EKS — Cluster health"
        stat  = "Maximum"
        metrics = [
          ["ContainerInsights", "cluster_failed_node_count", "ClusterName", module.eks.cluster_name],
          ["ContainerInsights", "cluster_number_of_running_pods", "ClusterName", module.eks.cluster_name],
        ]
      },
    ] : [],
    local.mon_rds ? [
      {
        title = "RDS — CPU & connections"
        stat  = "Average"
        metrics = [
          ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.db_identifier],
          ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.db_identifier],
        ]
      },
      {
        title = "RDS — Storage & memory (bytes)"
        stat  = "Average"
        metrics = [
          ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", var.db_identifier],
          ["AWS/RDS", "FreeableMemory", "DBInstanceIdentifier", var.db_identifier],
        ]
      },
    ] : [],
    local.mon_os ? [
      {
        title = "OpenSearch — Cluster health"
        stat  = "Maximum"
        metrics = [
          ["AWS/ES", "ClusterStatus.red", "DomainName", var.domain_name, "ClientId", local.monitoring_account_id],
          ["AWS/ES", "ClusterStatus.yellow", "DomainName", var.domain_name, "ClientId", local.monitoring_account_id],
          ["AWS/ES", "ClusterIndexWritesBlocked", "DomainName", var.domain_name, "ClientId", local.monitoring_account_id],
          ["AWS/ES", "Nodes", "DomainName", var.domain_name, "ClientId", local.monitoring_account_id],
        ]
      },
      {
        title = "OpenSearch — CPU & JVM (%)"
        stat  = "Maximum"
        metrics = [
          ["AWS/ES", "CPUUtilization", "DomainName", var.domain_name, "ClientId", local.monitoring_account_id],
          ["AWS/ES", "JVMMemoryPressure", "DomainName", var.domain_name, "ClientId", local.monitoring_account_id],
          ["AWS/ES", "OldGenJVMMemoryPressure", "DomainName", var.domain_name, "ClientId", local.monitoring_account_id],
        ]
      },
    ] : [],
    local.mon_neptune ? [
      {
        title = "Neptune — CPU, capacity & queue"
        stat  = "Average"
        metrics = [
          ["AWS/Neptune", "CPUUtilization", "DBClusterIdentifier", var.neptune_cluster_identifier],
          ["AWS/Neptune", "ServerlessDatabaseCapacity", "DBClusterIdentifier", var.neptune_cluster_identifier],
          ["AWS/Neptune", "MainRequestQueuePendingRequests", "DBClusterIdentifier", var.neptune_cluster_identifier],
        ]
      },
    ] : [],
    local.mon_bastion ? [
      {
        title = "EC2 bastion"
        stat  = "Average"
        metrics = [
          ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.bastion_ec2[0].id],
          ["AWS/EC2", "StatusCheckFailed", "InstanceId", aws_instance.bastion_ec2[0].id],
        ]
      },
    ] : [],
    local.mon_nfs ? [
      {
        title = "EC2 NFS"
        stat  = "Average"
        metrics = [
          ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.nfs_ec2[0].id],
          ["AWS/EC2", "StatusCheckFailed", "InstanceId", aws_instance.nfs_ec2[0].id],
        ]
      },
    ] : [],
    local.mon_efs ? [
      {
        title = "EFS"
        stat  = "Maximum"
        metrics = [
          ["AWS/EFS", "PercentIOLimit", "FileSystemId", aws_efs_file_system.this[0].id],
          ["AWS/EFS", "ClientConnections", "FileSystemId", aws_efs_file_system.this[0].id],
        ]
      },
    ] : [],
  )

  dashboard_body = {
    widgets = [
      for i, w in local.dashboard_widget_specs : {
        type   = "metric"
        width  = 12
        height = 6
        x      = (i % 2) * 12
        y      = floor(i / 2) * 6
        properties = {
          title   = w.title
          region  = var.region
          view    = "timeSeries"
          stacked = false
          stat    = w.stat
          period  = var.monitoring_alarm_period
          metrics = w.metrics
        }
      }
    ]
  }
}

resource "aws_cloudwatch_dashboard" "monitoring" {
  count          = var.enable_monitoring && var.enable_monitoring_dashboard && length(local.dashboard_widget_specs) > 0 ? 1 : 0
  dashboard_name = "${local.monitoring_name}-infra"
  dashboard_body = jsonencode(local.dashboard_body)
}
