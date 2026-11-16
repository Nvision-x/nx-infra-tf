################################################################################
# Database auto-alarms — Lambda that alarms every database it finds
#
# The alarms in cloudwatch-monitoring.tf cover the databases this module creates,
# one identifier each. Anything else (a new Neptune instance, a second replica,
# a DocumentDB cluster made by hand) went unmonitored until someone wrote more
# alarms, and Vanta's per-instance DB tests failed meanwhile.
#
# This Lambda reconciles the whole account+region on every run: every instance
# behind the RDS API (RDS, Aurora, Neptune, DocumentDB) gets CPU, freeable
# memory, storage and IO alarms on the monitoring SNS topic. It runs on RDS
# instance create/delete events and on a schedule.
#
# Terraform alarms stay the source of tuned thresholds: when one already exists
# on the same metric, the Lambda creates nothing for it. Opt an instance out
# with the tag nx:auto-alarms=off. IAM lives in nx-iam-tf
# (db_auto_alarms_role_arn input).
################################################################################

locals {
  db_auto_alarms_enabled  = var.enable_monitoring && var.monitoring_db_auto_alarms_enabled
  db_auto_alarms_function = "${local.monitoring_name}-db-auto-alarms"
}

resource "aws_cloudwatch_log_group" "db_auto_alarms" {
  count             = local.db_auto_alarms_enabled ? 1 : 0
  name              = "/aws/lambda/${local.db_auto_alarms_function}"
  retention_in_days = var.db_auto_alarms_log_retention_days
  tags              = var.tags
}

resource "aws_lambda_function" "db_auto_alarms" {
  count         = local.db_auto_alarms_enabled ? 1 : 0
  function_name = local.db_auto_alarms_function
  description   = "Creates CloudWatch alarms for every RDS/Aurora/Neptune/DocumentDB instance lacking them"
  role          = var.db_auto_alarms_role_arn
  runtime       = "python3.12"
  handler       = "db_auto_alarms.handler"
  # zip is committed (CI applies a saved plan in a separate job, so a
  # plan-time archive_file is absent at apply); rebuild after editing the py:
  #   cd files && zip -X db_auto_alarms.zip db_auto_alarms.py
  filename         = "${path.module}/files/db_auto_alarms.zip"
  source_code_hash = filebase64sha256("${path.module}/files/db_auto_alarms.zip")
  timeout          = 120
  memory_size      = 128
  # no reserved concurrency: runs are idempotent, so an overlap is harmless,
  # and reserving can fail on accounts with a low concurrency quota

  environment {
    variables = {
      # alarm names are <ALARM_PREFIX>.<instance>.<check>; nx-iam-tf scopes
      # alarm writes to this prefix
      ALARM_PREFIX             = local.db_auto_alarms_function
      ALARM_ACTIONS            = jsonencode(local.monitoring_alarm_actions)
      OK_ACTIONS               = jsonencode(local.monitoring_ok_actions)
      ALARM_TAGS               = jsonencode(merge(var.tags, { ManagedBy = local.db_auto_alarms_function }))
      OPT_OUT_TAG_KEY          = var.db_auto_alarms_opt_out_tag_key
      PERIOD                   = tostring(var.monitoring_alarm_period)
      EVALUATION_PERIODS       = tostring(var.monitoring_alarm_evaluation_periods)
      DATAPOINTS_TO_ALARM      = tostring(var.monitoring_datapoints_to_alarm)
      TREAT_MISSING_DATA       = var.monitoring_treat_missing_data
      CPU_THRESHOLD            = tostring(var.rds_cpu_threshold)
      FREEABLE_MEMORY_BYTES    = tostring(var.rds_freeable_memory_bytes_threshold)
      FREE_STORAGE_BYTES       = tostring(var.rds_free_storage_bytes_threshold)
      FREE_STORAGE_PERCENT     = tostring(var.db_auto_alarms_free_storage_percent)
      FREE_LOCAL_STORAGE_BYTES = tostring(var.db_auto_alarms_free_local_storage_bytes)
      DISK_QUEUE_DEPTH         = tostring(var.rds_disk_queue_depth_threshold)
      VOLUME_WRITE_IOPS        = tostring(var.db_auto_alarms_volume_write_iops_threshold)
    }
  }

  depends_on = [aws_cloudwatch_log_group.db_auto_alarms]
  tags       = var.tags

  lifecycle {
    precondition {
      condition     = var.db_auto_alarms_role_arn != ""
      error_message = "db_auto_alarms_role_arn is required when monitoring_db_auto_alarms_enabled = true. Enable enable_db_auto_alarms_role in nx-iam-tf and pass its db_auto_alarms_role_arn output."
    }
  }
}

# Fast path: a database instance was created, restored or deleted.
# Neptune and DocumentDB instances emit these too (they share the RDS event
# service). Any event triggers a full reconcile, so the exact IDs only matter
# for latency.
resource "aws_cloudwatch_event_rule" "db_auto_alarms_events" {
  count       = local.db_auto_alarms_enabled ? 1 : 0
  name        = "${local.db_auto_alarms_function}-events"
  description = "Reconcile database alarms when a DB instance is created, restored or deleted"
  event_pattern = jsonencode({
    source        = ["aws.rds"]
    "detail-type" = ["RDS DB Instance Event"]
    detail = {
      EventID = [
        "RDS-EVENT-0005", # DB instance created
        "RDS-EVENT-0003", # DB instance deleted
        "RDS-EVENT-0008", # restored from snapshot
        "RDS-EVENT-0019", # restored from point-in-time
        "RDS-EVENT-0043", # restored from backup
      ]
    }
  })
  tags = var.tags
}

# Safety net: catches anything an event missed (pre-existing instances,
# renamed instances, alarms deleted by hand).
resource "aws_cloudwatch_event_rule" "db_auto_alarms_schedule" {
  count               = local.db_auto_alarms_enabled ? 1 : 0
  name                = "${local.db_auto_alarms_function}-schedule"
  description         = "Periodic reconcile of database alarms"
  schedule_expression = var.db_auto_alarms_schedule_expression
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "db_auto_alarms_events" {
  count = local.db_auto_alarms_enabled ? 1 : 0
  rule  = aws_cloudwatch_event_rule.db_auto_alarms_events[0].name
  arn   = aws_lambda_function.db_auto_alarms[0].arn
}

resource "aws_cloudwatch_event_target" "db_auto_alarms_schedule" {
  count = local.db_auto_alarms_enabled ? 1 : 0
  rule  = aws_cloudwatch_event_rule.db_auto_alarms_schedule[0].name
  arn   = aws_lambda_function.db_auto_alarms[0].arn
}

resource "aws_lambda_permission" "db_auto_alarms_events" {
  count         = local.db_auto_alarms_enabled ? 1 : 0
  statement_id  = "AllowRdsEventsInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.db_auto_alarms[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.db_auto_alarms_events[0].arn
}

resource "aws_lambda_permission" "db_auto_alarms_schedule" {
  count         = local.db_auto_alarms_enabled ? 1 : 0
  statement_id  = "AllowScheduleInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.db_auto_alarms[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.db_auto_alarms_schedule[0].arn
}

# The Lambda raises when any alarm fails to apply, so a broken reconcile pages
# instead of silently leaving databases unmonitored.
resource "aws_cloudwatch_metric_alarm" "db_auto_alarms_errors" {
  count               = local.db_auto_alarms_enabled ? 1 : 0
  alarm_name          = "${local.db_auto_alarms_function}-errors"
  alarm_description   = "The database auto-alarms Lambda failed; check /aws/lambda/${local.db_auto_alarms_function}. New databases may be unmonitored."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = local.db_auto_alarms_function }
  statistic           = "Sum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  period              = 300
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}
