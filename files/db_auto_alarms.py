"""Database auto-alarms.

Makes sure every database instance behind the RDS API (RDS, Aurora, Neptune,
DocumentDB) has CloudWatch alarms for CPU, freeable memory, storage and IO,
whoever created it and however.

Every run reconciles the whole account and region. It is triggered by RDS
instance create/delete events (fast path) and on a schedule (catches anything
an event missed), so it is idempotent:

  * A check that already has an alarm not made by this function, typically a
    Terraform alarm with tuned thresholds, is left alone. Any alarm of ours
    for that check is deleted, so Terraform always wins.
  * Otherwise the function puts its own alarm, named <PREFIX>.<instance>.<check>.
  * Our alarms whose instance is gone or opted out are deleted.

Opt an instance out with the tag <OPT_OUT_TAG_KEY>=off.
"""

import json
import logging
import os
from dataclasses import dataclass, field

import boto3

log = logging.getLogger()
log.setLevel(logging.INFO)

rds = boto3.client("rds")
cw = boto3.client("cloudwatch")

PREFIX = os.environ["ALARM_PREFIX"]
ALARM_ACTIONS = json.loads(os.environ.get("ALARM_ACTIONS", "[]"))
OK_ACTIONS = json.loads(os.environ.get("OK_ACTIONS", "[]"))
OPT_OUT_TAG_KEY = os.environ.get("OPT_OUT_TAG_KEY", "nx:auto-alarms")
TAGS = [{"Key": k, "Value": v} for k, v in json.loads(os.environ.get("ALARM_TAGS", "{}")).items()]

PERIOD = int(os.environ.get("PERIOD", "300"))
EVALUATION_PERIODS = int(os.environ.get("EVALUATION_PERIODS", "3"))
DATAPOINTS_TO_ALARM = int(os.environ.get("DATAPOINTS_TO_ALARM", "2"))
TREAT_MISSING_DATA = os.environ.get("TREAT_MISSING_DATA", "missing")

CPU_THRESHOLD = float(os.environ.get("CPU_THRESHOLD", "85"))
FREEABLE_MEMORY_BYTES = float(os.environ.get("FREEABLE_MEMORY_BYTES", str(256 * 1024**2)))
FREE_STORAGE_BYTES = float(os.environ.get("FREE_STORAGE_BYTES", str(10 * 1024**3)))
FREE_STORAGE_PERCENT = float(os.environ.get("FREE_STORAGE_PERCENT", "10"))
FREE_LOCAL_STORAGE_BYTES = float(os.environ.get("FREE_LOCAL_STORAGE_BYTES", str(1 * 1024**3)))
DISK_QUEUE_DEPTH = float(os.environ.get("DISK_QUEUE_DEPTH", "64"))
VOLUME_WRITE_IOPS = float(os.environ.get("VOLUME_WRITE_IOPS", "1000000"))

NAMESPACES = {"neptune": "AWS/Neptune", "docdb": "AWS/DocDB"}
# Engines whose storage is a shared cluster volume: no per-instance
# FreeStorageSpace, only local (temp) storage on the instance.
CLUSTER_VOLUME_ENGINES = ("neptune", "docdb")


@dataclass
class Candidate:
    namespace: str
    metric: str
    dimensions: list
    comparison: str
    threshold: float
    statistic: str = "Average"
    unit_hint: str = ""


@dataclass
class Check:
    key: str
    label: str
    # Ordered by preference. The first one with data in the last two weeks is
    # used, else the first one (new instances have no data yet).
    candidates: list = field(default_factory=list)


def _dim(name, value):
    return [{"Name": name, "Value": value}]


def checks_for(db):
    engine = db["Engine"]
    inst = db["DBInstanceIdentifier"]
    cluster = db.get("DBClusterIdentifier")
    ns = NAMESPACES.get(engine, "AWS/RDS")
    idim = _dim("DBInstanceIdentifier", inst)
    cluster_volume = engine.startswith("aurora") or engine in CLUSTER_VOLUME_ENGINES

    checks = [
        Check("cpu", "CPU utilization", [Candidate(ns, "CPUUtilization", idim, "GreaterThanThreshold", CPU_THRESHOLD, unit_hint="%")]),
        Check("freeable-memory", "freeable memory", [Candidate(ns, "FreeableMemory", idim, "LessThanThreshold", FREEABLE_MEMORY_BYTES, unit_hint=" bytes")]),
    ]

    if cluster_volume:
        storage = Candidate(ns, "FreeLocalStorage", idim, "LessThanThreshold", FREE_LOCAL_STORAGE_BYTES, unit_hint=" bytes")
    else:
        allocated_bytes = float(db.get("AllocatedStorage") or 0) * 1024**3
        threshold = FREE_STORAGE_BYTES
        if allocated_bytes:
            threshold = min(FREE_STORAGE_BYTES, allocated_bytes * FREE_STORAGE_PERCENT / 100)
        storage = Candidate(ns, "FreeStorageSpace", idim, "LessThanThreshold", threshold, unit_hint=" bytes")
    checks.append(Check("free-storage", "free storage", [storage]))

    disk_queue = Candidate(ns, "DiskQueueDepth", idim, "GreaterThanThreshold", DISK_QUEUE_DEPTH)
    io = [disk_queue]
    if cluster:
        volume = Candidate(ns, "VolumeWriteIOPs", _dim("DBClusterIdentifier", cluster), "GreaterThanThreshold", VOLUME_WRITE_IOPS)
        # Neptune/DocDB publish no per-instance disk queue; the cluster
        # volume IOPS is their IO signal, so prefer it for new instances too.
        io = [volume, disk_queue] if engine in CLUSTER_VOLUME_ENGINES else [disk_queue, volume]
    checks.append(Check("io", "IO", io))
    return checks


def has_data(c):
    resp = cw.list_metrics(Namespace=c.namespace, MetricName=c.metric, Dimensions=c.dimensions)
    return bool(resp.get("Metrics"))


def pick(check):
    if len(check.candidates) == 1:
        return check.candidates[0]
    for c in check.candidates:
        if has_data(c):
            return c
    return check.candidates[0]


def foreign_alarms(c):
    """Alarms on this exact metric not made by us (Terraform, console)."""
    resp = cw.describe_alarms_for_metric(Namespace=c.namespace, MetricName=c.metric, Dimensions=c.dimensions)
    return [a["AlarmName"] for a in resp.get("MetricAlarms", []) if not a["AlarmName"].startswith(PREFIX + ".")]


def opted_out(db):
    return any(t["Key"] == OPT_OUT_TAG_KEY and t["Value"].lower() == "off" for t in db.get("TagList", []))


def list_instances():
    out = []
    for page in rds.get_paginator("describe_db_instances").paginate():
        out.extend(page["DBInstances"])
    return out


def list_our_alarms():
    names = []
    for page in cw.get_paginator("describe_alarms").paginate(AlarmNamePrefix=PREFIX + ".", AlarmTypes=["MetricAlarm"]):
        names.extend(a["AlarmName"] for a in page["MetricAlarms"])
    return names


def put_alarm(name, db, check, c):
    cw.put_metric_alarm(
        AlarmName=name,
        AlarmDescription=(
            f"[auto] {db['Engine']} {db['DBInstanceIdentifier']} {check.label}: "
            f"{c.metric} {'>' if c.comparison.startswith('Greater') else '<'} {c.threshold:g}{c.unit_hint}. "
            "Created by the db-auto-alarms Lambda (nx-infra-tf). To tune, define a Terraform alarm on the same metric; this one is then removed."
        ),
        Namespace=c.namespace,
        MetricName=c.metric,
        Dimensions=c.dimensions,
        Statistic=c.statistic,
        ComparisonOperator=c.comparison,
        Threshold=c.threshold,
        Period=PERIOD,
        EvaluationPeriods=EVALUATION_PERIODS,
        DatapointsToAlarm=DATAPOINTS_TO_ALARM,
        TreatMissingData=TREAT_MISSING_DATA,
        ActionsEnabled=True,
        AlarmActions=ALARM_ACTIONS,
        OKActions=OK_ACTIONS,
        Tags=TAGS,
    )


def handler(event, context):
    log.info("trigger: %s", json.dumps({k: event.get(k) for k in ("source", "detail-type", "resources")}, default=str))

    instances = list_instances()  # raises on failure: never delete alarms on a bad read
    existing = set(list_our_alarms())
    desired, put, kept_foreign, errors = set(), [], [], []

    for db in instances:
        inst = db["DBInstanceIdentifier"]
        if db.get("DBInstanceStatus") == "deleting" or opted_out(db):
            continue
        for check in checks_for(db):
            name = f"{PREFIX}.{inst}.{check.key}"
            try:
                c = pick(check)
                foreign = foreign_alarms(c)
                if foreign:
                    kept_foreign.append({"instance": inst, "check": check.key, "alarms": foreign})
                    continue
                put_alarm(name, db, check, c)
                desired.add(name)
                put.append({"alarm": name, "metric": f"{c.namespace}/{c.metric}"})
            except Exception as e:  # keep going; fail the invocation at the end
                log.exception("failed %s", name)
                errors.append(f"{name}: {e}")
                desired.add(name)  # don't delete what we failed to refresh

    stale = sorted(existing - desired)
    for i in range(0, len(stale), 100):
        cw.delete_alarms(AlarmNames=stale[i : i + 100])

    summary = {
        "instances": len(instances),
        "alarms_put": put,
        "covered_by_other_alarms": kept_foreign,
        "alarms_deleted": stale,
        "errors": errors,
    }
    log.info("summary: %s", json.dumps(summary))
    if errors:
        raise RuntimeError(f"{len(errors)} alarm(s) failed: {errors}")
    return summary
