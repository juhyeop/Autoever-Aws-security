"""
GuardDuty x Inspector 상관분석 Lambda  (설계문서 4장)

EventBridge가 GuardDuty finding을 감지하면 이 함수가 돌면서:

  1. 이벤트에서 대상 리소스(EC2 인스턴스 ID 등)를 뽑고
  2. 같은 리소스에 Inspector CVE finding이 있는지 조회한 뒤
  3. "행위 기반 이상탐지(GuardDuty) + 알려진 취약점(Inspector)" 을
     하나의 레코드로 합쳐 DynamoDB에 적재합니다. 대시보드는 이 테이블을 읽습니다.
  4. (옵션) Security Hub에 커스텀 finding으로 재게시해서
     Security Hub 화면에서도 상관관계가 보이게 합니다.

두 신호가 겹치면(= 수상하게 행동하는데 패치도 안 된 인스턴스) 우선순위를 올립니다.
"""

import datetime
import json
import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

TABLE_NAME = os.environ["FINDINGS_TABLE"]
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN") or None
REIMPORT_TO_SECURITY_HUB = os.environ.get("REIMPORT_TO_SECURITY_HUB", "false").lower() == "true"

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)
inspector = boto3.client("inspector2")
securityhub = boto3.client("securityhub")
sns = boto3.client("sns")
sts = boto3.client("sts")

# GuardDuty severity(숫자) -> 사람이 읽는 라벨.
# https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_findings.html
SEVERITY_LABELS = [
    (9.0, "CRITICAL"),
    (7.0, "HIGH"),
    (4.0, "MEDIUM"),
    (1.0, "LOW"),
]


def severity_label(score):
    for threshold, label in SEVERITY_LABELS:
        if score >= threshold:
            return label
    return "INFORMATIONAL"


def extract_resource(detail):
    """GuardDuty finding에서 대상 리소스 식별자를 뽑아냅니다."""
    resource = detail.get("resource", {})
    resource_type = resource.get("resourceType", "Unknown")

    if resource_type == "Instance":
        instance_id = resource.get("instanceDetails", {}).get("instanceId")
        return resource_type, instance_id

    if resource_type == "AccessKey":
        user = resource.get("accessKeyDetails", {}).get("userName")
        return resource_type, user

    if resource_type == "S3Bucket":
        buckets = resource.get("s3BucketDetails") or []
        return resource_type, buckets[0].get("name") if buckets else None

    return resource_type, None


def inspector_findings_for(instance_id):
    """해당 인스턴스의 Inspector CVE finding을 조회합니다."""
    if not instance_id:
        return []

    try:
        response = inspector.list_findings(
            filterCriteria={
                "resourceId": [{"comparison": "EQUALS", "value": instance_id}],
                "severity": [
                    {"comparison": "EQUALS", "value": "CRITICAL"},
                    {"comparison": "EQUALS", "value": "HIGH"},
                ],
            },
            maxResults=25,
        )
    except inspector.exceptions.AccessDeniedException:
        # Inspector가 꺼져 있거나 권한이 없는 경우 — 상관분석 없이 계속 진행합니다.
        logger.warning("Inspector 조회 권한이 없습니다. 상관분석을 건너뜁니다.")
        return []
    except Exception as exc:  # noqa: BLE001 - 상관분석 실패가 전체를 막으면 안 됩니다.
        logger.warning("Inspector 조회 실패: %s", exc)
        return []

    findings = []
    for item in response.get("findings", []):
        vuln = item.get("packageVulnerabilityDetails", {}) or {}
        findings.append(
            {
                "cve": vuln.get("vulnerabilityId") or item.get("title", "unknown"),
                "severity": item.get("severity"),
                "title": item.get("title"),
                "fixAvailable": item.get("fixAvailable"),
            }
        )
    return findings


def build_record(detail, resource_type, resource_id, cve_findings):
    gd_severity = float(detail.get("severity", 0))
    label = severity_label(gd_severity)

    # 두 신호가 겹치면 한 단계 올립니다. 이게 이 Lambda의 핵심 판단입니다.
    escalated = bool(cve_findings) and label in ("MEDIUM", "HIGH")
    final_label = {"MEDIUM": "HIGH", "HIGH": "CRITICAL"}[label] if escalated else label

    return {
        "finding_id": detail.get("id"),
        "source": "guardduty-inspector-correlator",
        "guardduty_type": detail.get("type"),
        "title": detail.get("title"),
        "description": detail.get("description"),
        "resource_type": resource_type,
        "resource_id": resource_id or "unknown",
        "guardduty_severity": str(gd_severity),
        "severity": final_label,
        "escalated": escalated,
        "cve_count": len(cve_findings),
        "cve_findings": cve_findings[:10],
        "region": detail.get("region"),
        "account_id": detail.get("accountId"),
        "created_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }


def reimport_to_security_hub(record):
    """합친 결과를 Security Hub에 커스텀 finding으로 재게시합니다."""
    account_id = sts.get_caller_identity()["Account"]
    region = os.environ["AWS_REGION"]
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()

    asff = {
        "SchemaVersion": "2018-10-08",
        "Id": f"correlated/{record['finding_id']}",
        "ProductArn": f"arn:aws:securityhub:{region}:{account_id}:product/{account_id}/default",
        "GeneratorId": "guardduty-inspector-correlator",
        "AwsAccountId": account_id,
        "Types": ["Unusual Behaviors/VM"],
        "CreatedAt": now,
        "UpdatedAt": now,
        "Severity": {"Label": record["severity"]},
        "Title": f"[상관분석] {record['title']}",
        "Description": (
            f"GuardDuty 이상행위와 Inspector 취약점 {record['cve_count']}건이 "
            f"같은 리소스({record['resource_id']})에서 함께 확인되었습니다."
        ),
        "Resources": [
            {
                "Type": "AwsEc2Instance" if record["resource_type"] == "Instance" else "Other",
                "Id": record["resource_id"],
                "Region": region,
            }
        ],
        "RecordState": "ACTIVE",
    }

    try:
        securityhub.batch_import_findings(Findings=[asff])
    except Exception as exc:  # noqa: BLE001
        logger.warning("Security Hub 재게시 실패: %s", exc)


def handler(event, context):  # noqa: ARG001 - context는 쓰지 않습니다.
    logger.info("수신 이벤트: %s", json.dumps(event)[:2000])

    detail = event.get("detail", {})
    if not detail.get("id"):
        logger.warning("GuardDuty finding 형식이 아닙니다. 건너뜁니다.")
        return {"status": "skipped"}

    resource_type, resource_id = extract_resource(detail)
    cve_findings = inspector_findings_for(resource_id if resource_type == "Instance" else None)
    record = build_record(detail, resource_type, resource_id, cve_findings)

    table.put_item(Item=record)
    logger.info(
        "적재 완료: %s severity=%s cve=%d escalated=%s",
        record["finding_id"],
        record["severity"],
        record["cve_count"],
        record["escalated"],
    )

    if REIMPORT_TO_SECURITY_HUB:
        reimport_to_security_hub(record)

    # 두 신호가 겹친 건만 알림을 보냅니다. 전부 보내면 알림 피로가 심합니다.
    if record["escalated"] and SNS_TOPIC_ARN:
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f"[{record['severity']}] 상관분석 탐지: {record['resource_id']}",
            Message=(
                f"GuardDuty: {record['title']}\n"
                f"리소스: {record['resource_type']} {record['resource_id']}\n"
                f"Inspector CVE: {record['cve_count']}건\n"
                f"  " + "\n  ".join(f"{c['cve']} ({c['severity']})" for c in record["cve_findings"][:5])
                + "\n\n행위 이상 + 알려진 취약점이 같은 리소스에서 확인되어 우선순위를 올렸습니다."
            ),
        )

    return {"status": "ok", "finding_id": record["finding_id"], "escalated": record["escalated"]}
