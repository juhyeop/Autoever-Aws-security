###############################################################################
# SSM Automation 플레이북 (ASR — Automated Security Response 방식)
#
# 문서 이름은 ASR- 로 시작합니다. 대시보드 IAM 정책이
# automation-definition/ASR-* 로만 실행을 허용하기 때문입니다(최소권한).
###############################################################################

data "aws_iam_policy_document" "automation_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ssm.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "automation" {
  name               = "${var.name_prefix}-ssm-automation"
  assume_role_policy = data.aws_iam_policy_document.automation_assume.json
}

data "aws_iam_policy_document" "automation" {
  statement {
    sid    = "RevokeOpenIngressRules"
    effect = "Allow"
    actions = [
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSecurityGroupRules",
      "ec2:RevokeSecurityGroupIngress",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "WriteAutomationLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:CreateLogGroup"]
    resources = ["arn:${data.aws_partition.current.partition}:logs:*:*:*"]
  }
}

resource "aws_iam_role_policy" "automation" {
  name   = "${var.name_prefix}-ssm-automation"
  role   = aws_iam_role.automation.id
  policy = data.aws_iam_policy_document.automation.json
}

###############################################################################
# 플레이북: 0.0.0.0/0 으로 열린 인바운드 규칙 회수
#
# 되돌릴 수 없는 작업이 아니고(규칙은 다시 추가 가능), 조직 고유 정책값도
# 필요 없어서 자동조치 기준 ①②를 만족합니다.
###############################################################################

resource "aws_ssm_document" "revoke_open_ingress" {
  name            = "${var.automation_document_prefix}RevokeOpenSecurityGroupRule"
  document_type   = "Automation"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "0.3"
    description   = "0.0.0.0/0 으로 열린 민감 포트 인바운드 규칙을 회수합니다."
    assumeRole    = "{{ AutomationAssumeRole }}"

    parameters = {
      SecurityGroupId = {
        type        = "String"
        description = "대상 Security Group ID"
        # sg- 로 시작하는 값만 받도록 제한
        allowedPattern = "^sg-[0-9a-f]{8,}$"
      }
      AutomationAssumeRole = {
        type        = "String"
        description = "Automation이 사용할 역할 ARN"
        default     = ""
      }
      SensitivePorts = {
        type        = "StringList"
        description = "인터넷 전체 공개를 허용하지 않을 포트"
        default     = ["22", "3306", "3389", "5432"]
      }
    }

    outputs = [
      "RevokeRules.RevokedCount",
      "RevokeRules.Before",
      "RevokeRules.After",
    ]

    mainSteps = [
      {
        name   = "RevokeRules"
        action = "aws:executeScript"
        # 실패해도 전체를 멈추지 않고 결과를 남깁니다.
        onFailure = "Abort"
        inputs = {
          Runtime = "python3.11"
          Handler = "revoke"
          InputPayload = {
            SecurityGroupId = "{{ SecurityGroupId }}"
            SensitivePorts  = "{{ SensitivePorts }}"
          }
          Script = <<-PYTHON
            import boto3

            def revoke(events, context):
                ec2 = boto3.client("ec2")
                sg_id = events["SecurityGroupId"]
                sensitive = {int(p) for p in events["SensitivePorts"]}

                before = ec2.describe_security_groups(GroupIds=[sg_id])["SecurityGroups"][0]
                before_rules = before.get("IpPermissions", [])

                to_revoke = []
                for perm in before_rules:
                    open_ranges = [r for r in perm.get("IpRanges", []) if r.get("CidrIp") == "0.0.0.0/0"]
                    if not open_ranges:
                        continue

                    from_port = perm.get("FromPort")
                    to_port = perm.get("ToPort")

                    # 모든 포트(-1)거나, 민감 포트를 포함하는 범위면 회수 대상
                    if from_port is None or to_port is None:
                        hit = True
                    else:
                        hit = any(from_port <= p <= to_port for p in sensitive)

                    if hit:
                        revoke_perm = {
                            "IpProtocol": perm["IpProtocol"],
                            "IpRanges": open_ranges,
                        }
                        if from_port is not None:
                            revoke_perm["FromPort"] = from_port
                        if to_port is not None:
                            revoke_perm["ToPort"] = to_port
                        to_revoke.append(revoke_perm)

                if to_revoke:
                    ec2.revoke_security_group_ingress(GroupId=sg_id, IpPermissions=to_revoke)

                after = ec2.describe_security_groups(GroupIds=[sg_id])["SecurityGroups"][0]

                # 대시보드 "조치 전/후" 화면에 그대로 쓸 수 있게 문자열로 정리해 돌려줍니다.
                return {
                    "RevokedCount": len(to_revoke),
                    "Before": str(before_rules),
                    "After": str(after.get("IpPermissions", [])),
                }
          PYTHON
        }
        outputs = [
          { Name = "RevokedCount", Selector = "$.Payload.RevokedCount", Type = "Integer" },
          { Name = "Before", Selector = "$.Payload.Before", Type = "String" },
          { Name = "After", Selector = "$.Payload.After", Type = "String" },
        ]
      }
    ]
  })

  tags = {
    Name = "${var.automation_document_prefix}RevokeOpenSecurityGroupRule"
  }
}
