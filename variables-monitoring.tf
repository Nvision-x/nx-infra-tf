################################################################################
# CloudWatch monitoring variables
#
# All monitoring knobs live in this file (kept separate from variables.tf on
# purpose). Alarms are provisioned in cloudwatch-monitoring.tf.
#
# Master switch: `enable_monitoring`. Each resource category has its own
# enable/disable flag, and every alarm's threshold / period is a variable so
# thresholds can be tuned per environment without touching the module.
#
# An alarm is created only when ALL of the following are true:
#   1. enable_monitoring = true
#   2. the category flag is true (e.g. monitoring_rds_enabled)
#   3. the underlying resource exists (e.g. enable_postgres)
################################################################################

# --------------------------------------------------------------------------- #
# Master + category switches
# --------------------------------------------------------------------------- #

variable "enable_monitoring" {
  description = "Master switch for all CloudWatch alarms, the alarm SNS topic, and the Amazon Q (chat) integration. Intended to be turned on for production."
  type        = bool
  default     = false
}

variable "monitoring_eks_enabled" {
  description = "Enable EKS / Container Insights alarms (requires the amazon-cloudwatch-observability addon, which this module installs)"
  type        = bool
  default     = true
}

variable "monitoring_rds_enabled" {
  description = "Enable RDS PostgreSQL alarms (only applied when enable_postgres = true)"
  type        = bool
  default     = true
}

variable "monitoring_opensearch_enabled" {
  description = "Enable OpenSearch alarms (only applied when enable_opensearch = true)"
  type        = bool
  default     = true
}

variable "monitoring_neptune_enabled" {
  description = "Enable Neptune alarms (only applied when enable_neptune = true)"
  type        = bool
  default     = true
}

variable "monitoring_ec2_enabled" {
  description = "Enable EC2 (bastion / NFS) alarms (only applied when the respective instance is created)"
  type        = bool
  default     = true
}

variable "monitoring_efs_enabled" {
  description = "Enable EFS alarms (only applied when enable_efs = true)"
  type        = bool
  default     = true
}

variable "enable_monitoring_dashboard" {
  description = "Create a single CloudWatch dashboard summarizing every monitored resource"
  type        = bool
  default     = true
}

# --------------------------------------------------------------------------- #
# Notification wiring (SNS + Amazon Q / AWS Chatbot)
# --------------------------------------------------------------------------- #

variable "monitoring_sns_topic_arn" {
  description = "Existing SNS topic ARN to publish alarms to. Leave empty to have this module create one."
  type        = string
  default     = ""
}

variable "monitoring_kms_key_id" {
  description = "KMS key id/ARN to encrypt the module-created alarm SNS topic (Security Hub SNS.1). Empty creates a customer-managed key with rotation enabled. Ignored when monitoring_sns_topic_arn is set."
  type        = string
  default     = ""
}

variable "monitoring_alarm_emails" {
  description = "Email addresses subscribed to the alarm SNS topic (only used when this module creates the topic). Each requires a one-time confirmation click."
  type        = list(string)
  default     = []
}

variable "monitoring_additional_alarm_action_arns" {
  description = "Extra action ARNs (e.g. PagerDuty/OpsGenie SNS, Lambda, autoscaling) added to every alarm's alarm_actions in addition to the alarm SNS topic"
  type        = list(string)
  default     = []
}

variable "monitoring_notify_on_ok" {
  description = "Also send a notification when an alarm returns to OK (sets ok_actions to the alarm SNS topic)"
  type        = bool
  default     = true
}

# Amazon Q Developer in chat applications (formerly AWS Chatbot) -> Slack.
# One-time manual step: authorize the Slack workspace in the Amazon Q / AWS
# Chatbot console for this account, then supply the two IDs below. Until both
# are set the SNS pipeline still deploys; only the Slack channel config is
# skipped.
variable "monitoring_slack_workspace_id" {
  description = "Slack workspace (team) ID authorized in the Amazon Q / AWS Chatbot console. Empty disables the Slack integration."
  type        = string
  default     = ""
}

variable "monitoring_slack_channel_id" {
  description = "Slack channel ID that alarm notifications are posted to. Empty disables the Slack integration."
  type        = string
  default     = ""
}

# --------------------------------------------------------------------------- #
# Common alarm timing
# --------------------------------------------------------------------------- #

variable "monitoring_alarm_period" {
  description = "Metric period in seconds for standard alarms"
  type        = number
  default     = 300
}

variable "monitoring_alarm_evaluation_periods" {
  description = "Number of periods evaluated before an alarm changes state"
  type        = number
  default     = 3
}

variable "monitoring_datapoints_to_alarm" {
  description = "Datapoints within the evaluation window that must breach to trigger. Null means use evaluation_periods (M-of-M)."
  type        = number
  default     = 2
}

variable "monitoring_treat_missing_data" {
  description = "How alarms treat missing data: missing | notBreaching | breaching | ignore"
  type        = string
  default     = "missing"

  validation {
    condition     = contains(["missing", "notBreaching", "breaching", "ignore"], var.monitoring_treat_missing_data)
    error_message = "monitoring_treat_missing_data must be one of: missing, notBreaching, breaching, ignore."
  }
}

variable "monitoring_alarm_name_prefix" {
  description = "Prefix for every alarm/dashboard name. Empty defaults to the cluster name."
  type        = string
  default     = ""
}

# --------------------------------------------------------------------------- #
# EKS / Container Insights thresholds (percent, cluster-wide worst node)
# --------------------------------------------------------------------------- #

variable "eks_node_cpu_threshold" {
  description = "Alarm when any node's CPU utilization (%) exceeds this"
  type        = number
  default     = 85
}

variable "eks_node_memory_threshold" {
  description = "Alarm when any node's memory utilization (%) exceeds this"
  type        = number
  default     = 85
}

variable "eks_node_filesystem_threshold" {
  description = "Alarm when any node's filesystem utilization (%) exceeds this"
  type        = number
  default     = 85
}

# --------------------------------------------------------------------------- #
# RDS PostgreSQL thresholds
# --------------------------------------------------------------------------- #

variable "rds_cpu_threshold" {
  description = "Alarm when RDS CPUUtilization (%) exceeds this"
  type        = number
  default     = 85
}

variable "rds_freeable_memory_bytes_threshold" {
  description = "Alarm when RDS FreeableMemory (bytes) drops below this (default 256 MiB)"
  type        = number
  default     = 268435456
}

variable "rds_free_storage_bytes_threshold" {
  description = "Alarm when RDS FreeStorageSpace (bytes) drops below this (default 10 GiB)"
  type        = number
  default     = 10737418240
}

variable "rds_connections_threshold" {
  description = "Alarm when RDS DatabaseConnections exceeds this"
  type        = number
  default     = 500
}

variable "rds_read_latency_threshold" {
  description = "Alarm when RDS ReadLatency (seconds) exceeds this"
  type        = number
  default     = 0.05
}

variable "rds_write_latency_threshold" {
  description = "Alarm when RDS WriteLatency (seconds) exceeds this"
  type        = number
  default     = 0.05
}

variable "rds_disk_queue_depth_threshold" {
  description = "Alarm when RDS DiskQueueDepth exceeds this"
  type        = number
  default     = 64
}

variable "rds_swap_usage_bytes_threshold" {
  description = "Alarm when RDS SwapUsage (bytes) exceeds this (default 512 MiB)"
  type        = number
  default     = 536870912
}

# --------------------------------------------------------------------------- #
# OpenSearch thresholds
# --------------------------------------------------------------------------- #

variable "opensearch_free_storage_mb_threshold" {
  description = "Alarm when OpenSearch per-node FreeStorageSpace (MB) drops below this (default 20 GB). AWS blocks writes at ~1 GB free."
  type        = number
  default     = 20480
}

variable "opensearch_cpu_threshold" {
  description = "Alarm when OpenSearch data-node CPUUtilization (%) exceeds this"
  type        = number
  default     = 85
}

variable "opensearch_jvm_pressure_threshold" {
  description = "Alarm when OpenSearch JVMMemoryPressure (%) exceeds this"
  type        = number
  default     = 80
}

variable "opensearch_jvm_pressure_statistic" {
  description = "Statistic for the OpenSearch JVMMemoryPressure alarm. Average smooths the per-GC sawtooth and avoids flapping around the threshold; Maximum is more sensitive."
  type        = string
  default     = "Maximum"

  validation {
    condition     = contains(["Maximum", "Average", "Minimum", "Sum"], var.opensearch_jvm_pressure_statistic)
    error_message = "opensearch_jvm_pressure_statistic must be one of: Maximum, Average, Minimum, Sum."
  }
}

variable "opensearch_jvm_pressure_period" {
  description = "Metric period (seconds) for the JVMMemoryPressure alarm. Null falls back to monitoring_alarm_period."
  type        = number
  default     = null
}

variable "opensearch_jvm_pressure_evaluation_periods" {
  description = "Evaluation periods for the JVMMemoryPressure alarm. Null falls back to monitoring_alarm_evaluation_periods."
  type        = number
  default     = null
}

variable "opensearch_jvm_pressure_datapoints_to_alarm" {
  description = "Datapoints-to-alarm for the JVMMemoryPressure alarm. Null falls back to monitoring_datapoints_to_alarm."
  type        = number
  default     = null
}

variable "opensearch_old_gen_jvm_pressure_threshold" {
  description = "Alarm when OpenSearch OldGenJVMMemoryPressure (%) exceeds this"
  type        = number
  default     = 80
}

variable "opensearch_master_cpu_threshold" {
  description = "Alarm when OpenSearch dedicated-master MasterCPUUtilization (%) exceeds this"
  type        = number
  default     = 50
}

variable "opensearch_master_jvm_pressure_threshold" {
  description = "Alarm when OpenSearch MasterJVMMemoryPressure (%) exceeds this"
  type        = number
  default     = 80
}

variable "opensearch_5xx_threshold" {
  description = "Alarm when OpenSearch 5xx responses in a period exceed this"
  type        = number
  default     = 10
}

variable "opensearch_min_nodes_threshold" {
  description = "Alarm when the number of reachable OpenSearch nodes drops below this. 0 = auto (data + master + coordinator node counts)."
  type        = number
  default     = 0
}

# --------------------------------------------------------------------------- #
# Neptune thresholds
# --------------------------------------------------------------------------- #

variable "neptune_cpu_threshold" {
  description = "Alarm when Neptune CPUUtilization (%) exceeds this"
  type        = number
  default     = 85
}

variable "neptune_capacity_utilization_threshold" {
  description = "Alarm when Neptune ServerlessDatabaseCapacity reaches this percent of neptune_max_ncu"
  type        = number
  default     = 90
}

variable "neptune_main_queue_pending_threshold" {
  description = "Alarm when Neptune MainRequestQueuePendingRequests exceeds this (request backpressure)"
  type        = number
  default     = 8000
}

# --------------------------------------------------------------------------- #
# EC2 (bastion / NFS) thresholds
# --------------------------------------------------------------------------- #

variable "ec2_cpu_threshold" {
  description = "Alarm when a monitored EC2 instance's CPUUtilization (%) exceeds this"
  type        = number
  default     = 90
}

# --------------------------------------------------------------------------- #
# EFS thresholds
# --------------------------------------------------------------------------- #

variable "efs_percent_io_limit_threshold" {
  description = "Alarm when EFS PercentIOLimit (%) exceeds this (approaching General Purpose IOPS ceiling)"
  type        = number
  default     = 90
}
