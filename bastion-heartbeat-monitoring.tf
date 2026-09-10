################################################################################
# Bastion heartbeat — Lambda probe + alarms
#
# EventBridge -> Lambda checks the bastion (SSM agent, SSH port, tailscaled,
# tailnet presence) and publishes NX/Bastion metrics; one alarm per check on
# the existing alarm SNS topic. Missing data breaches, so a dead probe alarms
# too. IAM lives in nx-iam-tf (bastion_heartbeat_role_arn input).
################################################################################

locals {
  heartbeat_enabled = local.mon_bastion && var.monitoring_bastion_heartbeat_enabled
  # SSH dial needs the Lambda inside the VPC; attachment created only for it
  heartbeat_ssh_enabled        = local.heartbeat_enabled && var.bastion_heartbeat_ssh_check_enabled
  heartbeat_tailscaled_enabled = local.heartbeat_enabled && var.bastion_heartbeat_tailscaled_check_enabled
  heartbeat_tailscale_enabled  = local.heartbeat_enabled && var.bastion_heartbeat_tailscale_secret_arn != "" && var.tailscale_hostname != ""
  heartbeat_function_name      = "${local.monitoring_name}-bastion-heartbeat"
  heartbeat_namespace          = var.bastion_heartbeat_metric_namespace
}
resource "aws_security_group" "bastion_heartbeat" {
  count       = local.heartbeat_ssh_enabled ? 1 : 0
  name        = "${local.heartbeat_function_name}-sg"
  description = "Bastion heartbeat Lambda ENIs"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

# bastion SG ingress for the SSH dial lives inline in bastion-ec2.tf

resource "aws_cloudwatch_log_group" "bastion_heartbeat" {
  count             = local.heartbeat_enabled ? 1 : 0
  name              = "/aws/lambda/${local.heartbeat_function_name}"
  retention_in_days = var.bastion_heartbeat_log_retention_days
  tags              = var.tags
}

resource "aws_lambda_function" "bastion_heartbeat" {
  count         = local.heartbeat_enabled ? 1 : 0
  function_name = local.heartbeat_function_name
  role          = var.bastion_heartbeat_role_arn
  runtime       = "python3.12"
  handler       = "bastion_heartbeat.handler"
  # zip is committed (CI applies a saved plan in a separate job, so a
  # plan-time archive_file is absent at apply); rebuild after editing the py:
  #   cd files && zip -X bastion_heartbeat.zip bastion_heartbeat.py
  filename         = "${path.module}/files/bastion_heartbeat.zip"
  source_code_hash = filebase64sha256("${path.module}/files/bastion_heartbeat.zip")
  timeout          = 60 # tailscaled RunCommand check polls for up to ~20s
  memory_size      = 128

  # private subnets: AWS/Tailscale APIs stay reachable through the NAT
  dynamic "vpc_config" {
    for_each = local.heartbeat_ssh_enabled ? [1] : []
    content {
      subnet_ids         = var.private_subnets
      security_group_ids = [aws_security_group.bastion_heartbeat[0].id]
    }
  }

  environment {
    variables = {
      INSTANCE_ID          = aws_instance.bastion_ec2[0].id
      METRIC_NAMESPACE     = local.heartbeat_namespace
      MAX_SSM_PING_AGE     = tostring(var.bastion_heartbeat_max_ssm_ping_age_seconds)
      SSH_CHECK_HOST       = local.heartbeat_ssh_enabled ? aws_instance.bastion_ec2[0].private_ip : ""
      SSH_CHECK_PORT       = "22"
      TAILSCALED_CHECK     = local.heartbeat_tailscaled_enabled ? "1" : "0"
      TAILSCALE_SECRET_ARN = var.bastion_heartbeat_tailscale_secret_arn
      TAILSCALE_HOSTNAME   = var.tailscale_hostname
      TAILSCALE_TAILNET    = var.bastion_heartbeat_tailscale_tailnet
      MAX_TS_SEEN_AGE      = tostring(var.bastion_heartbeat_max_tailscale_seen_age_seconds)
    }
  }

  depends_on = [aws_cloudwatch_log_group.bastion_heartbeat]
  tags       = var.tags

  lifecycle {
    precondition {
      condition     = var.bastion_heartbeat_role_arn != ""
      error_message = "bastion_heartbeat_role_arn is required when the bastion heartbeat is enabled. Enable enable_bastion_heartbeat_role in nx-iam-tf and pass its bastion_heartbeat_role_arn output."
    }
  }
}

resource "aws_cloudwatch_event_rule" "bastion_heartbeat" {
  count               = local.heartbeat_enabled ? 1 : 0
  name                = "${local.heartbeat_function_name}-schedule"
  description         = "Triggers the bastion heartbeat probe"
  schedule_expression = var.bastion_heartbeat_schedule_expression
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "bastion_heartbeat" {
  count = local.heartbeat_enabled ? 1 : 0
  rule  = aws_cloudwatch_event_rule.bastion_heartbeat[0].name
  arn   = aws_lambda_function.bastion_heartbeat[0].arn
}

resource "aws_lambda_permission" "bastion_heartbeat" {
  count         = local.heartbeat_enabled ? 1 : 0
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.bastion_heartbeat[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.bastion_heartbeat[0].arn
}

# Alarms: < 1 on a 0/1 metric, missing data breaches.

resource "aws_cloudwatch_metric_alarm" "bastion_ssm_agent" {
  count               = local.heartbeat_enabled ? 1 : 0
  alarm_name          = "${local.monitoring_name}-bastion-ssm-agent-unreachable"
  alarm_description   = "Bastion SSM agent has not pinged within ${var.bastion_heartbeat_max_ssm_ping_age_seconds}s — instance is likely unreachable (network/DNS/agent failure)"
  namespace           = local.heartbeat_namespace
  metric_name         = "SSMAgentHealthy"
  dimensions          = { InstanceId = aws_instance.bastion_ec2[0].id }
  statistic           = "Minimum"
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  period              = var.bastion_heartbeat_alarm_period
  evaluation_periods  = var.bastion_heartbeat_alarm_evaluation_periods
  datapoints_to_alarm = var.bastion_heartbeat_datapoints_to_alarm
  treat_missing_data  = "breaching"
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "bastion_ssh_unreachable" {
  count               = local.heartbeat_ssh_enabled ? 1 : 0
  alarm_name          = "${local.monitoring_name}-bastion-ssh-unreachable"
  alarm_description   = "Bastion TCP port 22 is not accepting connections from inside the VPC"
  namespace           = local.heartbeat_namespace
  metric_name         = "SshPortReachable"
  dimensions          = { InstanceId = aws_instance.bastion_ec2[0].id }
  statistic           = "Minimum"
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  period              = var.bastion_heartbeat_alarm_period
  evaluation_periods  = var.bastion_heartbeat_alarm_evaluation_periods
  datapoints_to_alarm = var.bastion_heartbeat_datapoints_to_alarm
  treat_missing_data  = "breaching"
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "bastion_tailscaled_inactive" {
  count               = local.heartbeat_tailscaled_enabled ? 1 : 0
  alarm_name          = "${local.monitoring_name}-bastion-tailscaled-inactive"
  alarm_description   = "systemctl reports tailscaled is not active on the bastion (or the SSM RunCommand probe could not reach it)"
  namespace           = local.heartbeat_namespace
  metric_name         = "TailscaledServiceActive"
  dimensions          = { InstanceId = aws_instance.bastion_ec2[0].id }
  statistic           = "Minimum"
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  period              = var.bastion_heartbeat_alarm_period
  evaluation_periods  = var.bastion_heartbeat_alarm_evaluation_periods
  datapoints_to_alarm = var.bastion_heartbeat_datapoints_to_alarm
  treat_missing_data  = "breaching"
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "bastion_tailscale_offline" {
  count               = local.heartbeat_tailscale_enabled ? 1 : 0
  alarm_name          = "${local.monitoring_name}-bastion-tailscale-offline"
  alarm_description   = "Tailscale device ${var.tailscale_hostname} (exit node) has not been seen on the tailnet within ${var.bastion_heartbeat_max_tailscale_seen_age_seconds}s"
  namespace           = local.heartbeat_namespace
  metric_name         = "TailscaleDeviceOnline"
  dimensions          = { Hostname = var.tailscale_hostname }
  statistic           = "Minimum"
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  period              = var.bastion_heartbeat_alarm_period
  evaluation_periods  = var.bastion_heartbeat_alarm_evaluation_periods
  datapoints_to_alarm = var.bastion_heartbeat_datapoints_to_alarm
  treat_missing_data  = "breaching"
  alarm_actions       = local.monitoring_alarm_actions
  ok_actions          = local.monitoring_ok_actions
  tags                = var.tags
}
