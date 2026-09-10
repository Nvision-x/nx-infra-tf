"""Bastion heartbeat probe. Publishes one 0/1 metric per check:

  SSMAgentHealthy         - SSM agent pinged within MAX_SSM_PING_AGE
  SshPortReachable        - TCP dial to the bastion SSH port
  TailscaledServiceActive - systemctl is-active tailscaled via SSM RunCommand
  TailscaleDeviceOnline   - tailnet device seen within MAX_TS_SEEN_AGE

On check errors the metric is skipped; the alarms treat missing as breaching.
"""
import json
import os
import socket
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone

import boto3

INSTANCE_ID = os.environ["INSTANCE_ID"]
NAMESPACE = os.environ.get("METRIC_NAMESPACE", "NX/Bastion")
MAX_SSM_PING_AGE = int(os.environ.get("MAX_SSM_PING_AGE", "600"))
SSH_CHECK_HOST = os.environ.get("SSH_CHECK_HOST", "")
SSH_CHECK_PORT = int(os.environ.get("SSH_CHECK_PORT", "22"))
TAILSCALED_CHECK = os.environ.get("TAILSCALED_CHECK", "") == "1"
TS_SECRET_ARN = os.environ.get("TAILSCALE_SECRET_ARN", "")
TS_HOSTNAME = os.environ.get("TAILSCALE_HOSTNAME", "")
TS_TAILNET = os.environ.get("TAILSCALE_TAILNET", "-")
MAX_TS_SEEN_AGE = int(os.environ.get("MAX_TS_SEEN_AGE", "600"))

cloudwatch = boto3.client("cloudwatch")
ssm = boto3.client("ssm")


def ssm_agent_healthy():
    info = ssm.describe_instance_information(
        Filters=[{"Key": "InstanceIds", "Values": [INSTANCE_ID]}]
    )["InstanceInformationList"]
    if not info:
        return 0
    # PingStatus lags ~15 min; the ping age is the signal
    age = (datetime.now(timezone.utc) - info[0]["LastPingDateTime"]).total_seconds()
    return 1 if info[0]["PingStatus"] == "Online" and age <= MAX_SSM_PING_AGE else 0


def ssh_port_reachable():
    try:
        with socket.create_connection((SSH_CHECK_HOST, SSH_CHECK_PORT), timeout=5):
            return 1
    except OSError:
        return 0


def tailscaled_service_active():
    command_id = ssm.send_command(
        InstanceIds=[INSTANCE_ID],
        DocumentName="AWS-RunShellScript",
        Parameters={"commands": ["systemctl is-active tailscaled"]},
        TimeoutSeconds=30,
    )["Command"]["CommandId"]
    for _ in range(10):
        time.sleep(2)
        try:
            inv = ssm.get_command_invocation(
                CommandId=command_id, InstanceId=INSTANCE_ID
            )
        except ssm.exceptions.InvocationDoesNotExist:
            continue
        if inv["Status"] in ("Success", "Failed", "Cancelled", "TimedOut", "DeliveryTimedOut"):
            return (
                1
                if inv["Status"] == "Success"
                and inv["StandardOutputContent"].strip() == "active"
                else 0
            )
    return 0  # agent never picked the command up


def tailscale_token():
    secret = json.loads(
        boto3.client("secretsmanager").get_secret_value(SecretId=TS_SECRET_ARN)[
            "SecretString"
        ]
    )
    if "api_key" in secret:
        return secret["api_key"]
    # OAuth client: exchange for a short-lived token
    body = urllib.parse.urlencode(
        {
            "client_id": secret["oauth_client_id"],
            "client_secret": secret["oauth_client_secret"],
        }
    ).encode()
    req = urllib.request.Request(
        "https://api.tailscale.com/api/v2/oauth/token", data=body
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read())["access_token"]


def tailscale_device_online():
    req = urllib.request.Request(
        f"https://api.tailscale.com/api/v2/tailnet/{urllib.parse.quote(TS_TAILNET)}/devices",
        headers={"Authorization": f"Bearer {tailscale_token()}"},
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        devices = json.loads(resp.read())["devices"]
    for device in devices:
        names = {device.get("hostname"), device.get("name", "").split(".")[0]}
        if TS_HOSTNAME in names:
            seen = datetime.fromisoformat(device["lastSeen"].replace("Z", "+00:00"))
            age = (datetime.now(timezone.utc) - seen).total_seconds()
            return 1 if age <= MAX_TS_SEEN_AGE else 0
    return 0  # not registered on the tailnet at all


def put_metric(name, value, dimensions):
    cloudwatch.put_metric_data(
        Namespace=NAMESPACE,
        MetricData=[
            {
                "MetricName": name,
                "Value": value,
                "Unit": "None",
                "Dimensions": [
                    {"Name": k, "Value": v} for k, v in dimensions.items()
                ],
            }
        ],
    )


def handler(event, context):
    checks = [("SSMAgentHealthy", ssm_agent_healthy, {"InstanceId": INSTANCE_ID})]
    if SSH_CHECK_HOST:
        checks.append(("SshPortReachable", ssh_port_reachable, {"InstanceId": INSTANCE_ID}))
    if TAILSCALED_CHECK:
        checks.append(("TailscaledServiceActive", tailscaled_service_active, {"InstanceId": INSTANCE_ID}))
    if TS_SECRET_ARN and TS_HOSTNAME:
        checks.append(("TailscaleDeviceOnline", tailscale_device_online, {"Hostname": TS_HOSTNAME}))

    results = {}
    for name, check, dimensions in checks:
        try:
            results[name] = check()
            put_metric(name, results[name], dimensions)
        except Exception as exc:  # skip metric -> missing data -> alarm
            print(f"{name} check failed: {exc}")
    print(json.dumps(results))
    return results
