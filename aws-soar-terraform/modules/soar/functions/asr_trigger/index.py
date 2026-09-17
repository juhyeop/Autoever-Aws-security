"""
자동조치 판단 · 실행요청 Lambda  (설계문서 2장 / 5장)

Security Hub finding을 받아서 "자동으로 고쳐도 되는 건인가"를 판단하고,
맞으면 SSM Automation 플레이북을 실행합니다.

자동조치 기준은 설계문서에서 팀이 정한 두 가지 원칙 그대로입니다.

  ① 조직 고유의 정책값이 필요 없을 것
     (예: "SG가 0.0.0.0/0으로 열렸다"는 누가 봐도 설정 오류)
  ② 잘못 실행돼도 서비스가 되돌릴 수 없이 끊기지 않을 것

여기에 안전장치를 하나 더 둡니다.

  ③ 대상 리소스에 AutoRemediation=enabled 태그가 있을 것

③ 덕분에 같은 종류의 finding이라도 "MySQL 자동" 인스턴스만 자동으로 고쳐지고,
"MySQL 수동" 인스턴스는 사람이 확인하도록 SNS 알림만 갑니다.
DB를 2대 두는 시연이 코드로 구현되는 지점입니다.
"""

import json
import logging
import os
import re

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

AUTOMATION_DOCUMENT = os.environ["AUTOMATION_DOCUMENT"]
AUTOMATION_ROLE_ARN = os.environ["AUTOMATION_ROLE_ARN"]
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN") or None
AUTO_REMEDIATION_ENABLED = os.environ.get("AUTO_REMEDIATION_ENABLED", "true").lower() == "true"
REQUIRED_TAG_KEY = os.environ.get("REQUIRED_TAG_KEY", "AutoRemediation")
REQUIRED_TAG_VALUE = os.environ.get("REQUIRED_TAG_VALUE", "enabled")

ssm = boto3.client("ssm")
ec2 = boto3.client("ec2")
sns = boto3.client("sns")

# 자동조치 대상으로 인정할 finding 패턴.
# 화이트리스트 방식입니다 — 여기 없는 건 전부 수동으로 넘어갑니다.
AUTO_REMEDIABLE_PATTERNS = [
    r"security\s*group.*(0\.0\.0\.0/0|unrestricted|open to the world)",
    r"restricted[-_]?(common[-_]?ports|incoming[-_]?traffic)",
    r"should not allow unrestricted",
    r"(3306|22|3389|5432).*(0\.0\.0\.0/0|unrestricted)",
]

SG_ID_RE = re.compile(r"(sg-[0-9a-f]{8,})")


def is_auto_remediable(finding):
    """finding 제목/설명이 자동조치 화이트리스트에 걸리는지 확인합니다."""
    haystack = " ".join(
        [
            finding.get("Title", ""),
            finding.get("Description", ""),
            finding.get("GeneratorId", ""),
        ]
    ).lower()

    return any(re.search(pattern, haystack) for pattern in AUTO_REMEDIABLE_PATTERNS)


def extract_security_group_id(finding):
    """finding에서 대상 Security Group ID를 뽑아냅니다."""
    for resource in finding.get("Resources", []):
        rid = resource.get("Id", "")
        match = SG_ID_RE.search(rid)
        if match:
            return match.group(1)

        # EC2 인스턴스가 대상이면 그 인스턴스에 붙은 SG를 봅니다.
        if resource.get("Type") == "AwsEc2Instance":
            instance_match = re.search(r"(i-[0-9a-f]{8,})", rid)
            if instance_match:
                return security_group_of_instance(instance_match.group(1))

    # 마지막 수단: 본문 어딘가에 sg-xxxx 가 있는지
    match = SG_ID_RE.search(json.dumps(finding))
    return match.group(1) if match else None


def security_group_of_instance(instance_id):
    try:
        response = ec2.describe_instances(InstanceIds=[instance_id])
        for reservation in response["Reservations"]:
            for instance in reservation["Instances"]:
                groups = instance.get("SecurityGroups", [])
                if groups:
                    return groups[0]["GroupId"]
    except Exception as exc:  # noqa: BLE001
        logger.warning("인스턴스 %s 의 SG 조회 실패: %s", instance_id, exc)
    return None


def has_required_tag(security_group_id):
    """③ 안전장치: 대상 SG에 자동조치 허용 태그가 있는지 확인합니다."""
    try:
        response = ec2.describe_security_groups(GroupIds=[security_group_id])
    except Exception as exc:  # noqa: BLE001
        logger.warning("SG %s 조회 실패: %s", security_group_id, exc)
        return False

    for group in response.get("SecurityGroups", []):
        for tag in group.get("Tags", []):
            if tag.get("Key") == REQUIRED_TAG_KEY and tag.get("Value") == REQUIRED_TAG_VALUE:
                return True
    return False


def notify(subject, message):
    if not SNS_TOPIC_ARN:
        logger.info("SNS 토픽이 없어 알림을 건너뜁니다: %s", subject)
        return
    sns.publish(TopicArn=SNS_TOPIC_ARN, Subject=subject[:100], Message=message)


def start_remediation(security_group_id, finding):
    response = ssm.start_automation_execution(
        DocumentName=AUTOMATION_DOCUMENT,
        Parameters={
            "SecurityGroupId": [security_group_id],
            "AutomationAssumeRole": [AUTOMATION_ROLE_ARN],
        },
    )
    execution_id = response["AutomationExecutionId"]

    logger.info("자동조치 실행: sg=%s execution=%s", security_group_id, execution_id)
    notify(
        f"[자동조치 실행] {security_group_id}",
        (
            f"finding: {finding.get('Title')}\n"
            f"대상 SG: {security_group_id}\n"
            f"플레이북: {AUTOMATION_DOCUMENT}\n"
            f"실행 ID: {execution_id}\n\n"
            "0.0.0.0/0 으로 열린 인바운드 규칙을 회수했습니다. "
            "대시보드 '조치 관리' 탭에서 전/후 상태를 확인하세요."
        ),
    )
    return execution_id


def handle_finding(finding):
    title = finding.get("Title", "(제목 없음)")
    severity = finding.get("Severity", {}).get("Label", "UNKNOWN")

    # 이미 해결된 finding은 무시합니다.
    if finding.get("RecordState") == "ARCHIVED":
        return {"title": title, "action": "skipped-archived"}
    if finding.get("Compliance", {}).get("Status") == "PASSED":
        return {"title": title, "action": "skipped-passed"}

    if not is_auto_remediable(finding):
        logger.info("수동 대응 대상: %s", title)
        notify(
            f"[{severity}] 수동 확인 필요: {title}",
            (
                f"{finding.get('Description', '')}\n\n"
                "자동조치 화이트리스트에 없는 유형이라 담당자 확인이 필요합니다.\n"
                "대시보드 '취약점 목록'에서 조치 방안을 확인하세요."
            ),
        )
        return {"title": title, "action": "manual"}

    security_group_id = extract_security_group_id(finding)
    if not security_group_id:
        logger.warning("대상 SG를 찾지 못했습니다: %s", title)
        return {"title": title, "action": "manual-no-target"}

    if not has_required_tag(security_group_id):
        logger.info(
            "SG %s 에 %s=%s 태그가 없어 자동조치하지 않습니다.",
            security_group_id,
            REQUIRED_TAG_KEY,
            REQUIRED_TAG_VALUE,
        )
        notify(
            f"[{severity}] 수동 확인 필요: {title}",
            (
                f"대상 SG: {security_group_id}\n"
                f"자동조치 허용 태그({REQUIRED_TAG_KEY}={REQUIRED_TAG_VALUE})가 없어 "
                "실행하지 않았습니다. 담당자가 직접 확인해 주세요."
            ),
        )
        return {"title": title, "action": "manual-untagged", "security_group_id": security_group_id}

    if not AUTO_REMEDIATION_ENABLED:
        logger.info("자동조치가 꺼져 있어 판단만 합니다(dry-run): %s", security_group_id)
        notify(
            f"[DRY-RUN] 자동조치 대상: {security_group_id}",
            (
                f"finding: {title}\n"
                "enable_auto_remediation=false 라 실제 실행은 하지 않았습니다.\n"
                f"켜면 {AUTOMATION_DOCUMENT} 플레이북이 실행됩니다."
            ),
        )
        return {"title": title, "action": "dry-run", "security_group_id": security_group_id}

    execution_id = start_remediation(security_group_id, finding)
    return {
        "title": title,
        "action": "auto-remediated",
        "security_group_id": security_group_id,
        "execution_id": execution_id,
    }


def handler(event, context):  # noqa: ARG001
    logger.info("수신 이벤트: %s", json.dumps(event)[:2000])

    findings = event.get("detail", {}).get("findings", [])
    if not findings:
        logger.warning("finding이 없는 이벤트입니다.")
        return {"status": "skipped", "results": []}

    results = [handle_finding(finding) for finding in findings]
    logger.info("처리 결과: %s", json.dumps(results, ensure_ascii=False))
    return {"status": "ok", "results": results}
