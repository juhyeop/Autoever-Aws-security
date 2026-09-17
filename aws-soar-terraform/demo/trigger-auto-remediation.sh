#!/usr/bin/env bash
#
# 자동조치 시연 스크립트 (설계문서 2장 "MySQL 자동" 시나리오)
#
#   1. MySQL-자동 인스턴스의 SG에 3306/0.0.0.0/0 규칙을 넣습니다 (= 침해사례 재현)
#   2. 조치 전 상태를 보여주고
#   3. asr_trigger Lambda를 바로 호출합니다
#      (Config → Security Hub 경로는 몇 분 걸려서 발표 중에는 느립니다.
#       실제 파이프라인이 도는지 확인하려면 --wait 를 주고 기다리세요.)
#   4. 조치 후 상태를 다시 보여줍니다
#
# 사용법:
#   ./trigger-auto-remediation.sh              # 자동(태그 있는 SG) 시연
#   ./trigger-auto-remediation.sh --manual     # 수동(태그 없는 SG) 대조군 시연
#   ./trigger-auto-remediation.sh --wait       # 실제 Config/Security Hub 경로로 기다리기
#
set -euo pipefail

cd "$(dirname "$0")/.."

MODE="auto"
WAIT=false
for arg in "$@"; do
  case "$arg" in
    --manual) MODE="manual" ;;
    --wait)   WAIT=true ;;
    *) echo "알 수 없는 옵션: $arg"; exit 1 ;;
  esac
done

if [ "$MODE" = "auto" ]; then
  SG_ID=$(terraform output -raw mysql_auto_security_group_id)
  echo "대상: MySQL-자동 SG ($SG_ID) — AutoRemediation=enabled 태그 있음"
else
  SG_ID=$(terraform output -raw mysql_manual_security_group_id)
  echo "대상: MySQL-수동 SG ($SG_ID) — 태그 없음 → 알림만 가야 정상"
fi

REGION=$(terraform output -raw region)
LAMBDA=$(terraform output -raw asr_trigger_function_name)

echo
echo "=== 1단계: 침해사례 재현 — 3306 포트를 인터넷 전체에 개방 ==="
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp --port 3306 --cidr 0.0.0.0/0 \
  --region "$REGION" >/dev/null 2>&1 || echo "  (이미 열려 있습니다)"

echo
echo "=== 2단계: 조치 전 인바운드 규칙 ==="
aws ec2 describe-security-groups --group-ids "$SG_ID" --region "$REGION" \
  --query 'SecurityGroups[0].IpPermissions[?contains(to_string(IpRanges), `0.0.0.0/0`)]' \
  --output json

if [ "$WAIT" = true ]; then
  echo
  echo "=== 3단계: 실제 파이프라인 대기 (Config → Security Hub → EventBridge → Lambda) ==="
  echo "보통 5~15분 걸립니다. Security Hub 콘솔에서 finding이 뜨는지 지켜보세요."
  echo "중단하려면 Ctrl+C."
  for i in $(seq 1 60); do
    sleep 30
    OPEN=$(aws ec2 describe-security-groups --group-ids "$SG_ID" --region "$REGION" \
      --query 'length(SecurityGroups[0].IpPermissions[?contains(to_string(IpRanges), `0.0.0.0/0`)])' \
      --output text)
    printf "  [%02d/60] 남은 공개 규칙: %s\n" "$i" "$OPEN"
    [ "$OPEN" = "0" ] && break
  done
else
  echo
  echo "=== 3단계: asr_trigger Lambda 직접 호출 (시연용 지름길) ==="
  cat >/tmp/demo-finding.json <<JSON
{
  "detail": {
    "findings": [
      {
        "Id": "demo/open-security-group/$SG_ID",
        "GeneratorId": "security-control/EC2.19",
        "Title": "Security group should not allow unrestricted access to port 3306",
        "Description": "이 Security Group은 3306 포트를 0.0.0.0/0 으로 개방하고 있습니다.",
        "Severity": { "Label": "HIGH" },
        "RecordState": "ACTIVE",
        "Workflow": { "Status": "NEW" },
        "Resources": [
          {
            "Type": "AwsEc2SecurityGroup",
            "Id": "arn:aws:ec2:$REGION::security-group/$SG_ID"
          }
        ]
      }
    ]
  }
}
JSON

  aws lambda invoke \
    --function-name "$LAMBDA" \
    --region "$REGION" \
    --cli-binary-format raw-in-base64-out \
    --payload file:///tmp/demo-finding.json \
    /tmp/demo-response.json >/dev/null

  echo "Lambda 응답:"
  cat /tmp/demo-response.json | python3 -m json.tool 2>/dev/null || cat /tmp/demo-response.json
  echo
  echo "  (SSM Automation이 도는 데 10~20초 걸립니다)"
  sleep 20
fi

echo
echo "=== 4단계: 조치 후 인바운드 규칙 ==="
aws ec2 describe-security-groups --group-ids "$SG_ID" --region "$REGION" \
  --query 'SecurityGroups[0].IpPermissions[?contains(to_string(IpRanges), `0.0.0.0/0`)]' \
  --output json

echo
if [ "$MODE" = "auto" ]; then
  echo "기대 결과: 위 목록이 비어 있어야 합니다 (SOAR가 규칙을 회수함)."
else
  echo "기대 결과: 규칙이 그대로 남아 있고, SNS로 '수동 확인 필요' 알림만 와야 합니다."
  echo "정리하려면 직접 지우세요:"
  echo "  aws ec2 revoke-security-group-ingress --group-id $SG_ID --protocol tcp --port 3306 --cidr 0.0.0.0/0 --region $REGION"
fi
