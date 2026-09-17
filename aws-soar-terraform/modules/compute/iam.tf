###############################################################################
# 인스턴스 IAM — 설계문서의 "읽기 전용 / 실행 전용 역할 분리" 그대로 구현
#
#   base      : 전 인스턴스 공통. SSM Session Manager 접속 + CloudWatch Agent 지표 전송.
#   dashboard : base + (1) 탐지 결과 읽기 전용  (2) 승인된 플레이북만 실행
#
# 읽기와 실행을 분리해 둔 이유: 대시보드 코드에 버그가 있어도 조회 화면 때문에
# 의도치 않은 조치가 실행되지 않게 하기 위함입니다.
###############################################################################

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

###############################################################################
# 공통 역할
###############################################################################

resource "aws_iam_role" "base" {
  name               = "${var.name_prefix}-ec2-base"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

# SSM Session Manager로 접속하기 위한 관리형 정책 (키페어 없이도 셸 접속 가능)
resource "aws_iam_role_policy_attachment" "base_ssm" {
  role       = aws_iam_role.base.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# CloudWatch Agent가 메모리/디스크 지표를 올리기 위한 관리형 정책
resource "aws_iam_role_policy_attachment" "base_cw_agent" {
  role       = aws_iam_role.base.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "base" {
  name = "${var.name_prefix}-ec2-base"
  role = aws_iam_role.base.name
}

###############################################################################
# DB 인스턴스용 역할 — 공통 + Secrets Manager에서 자기 비밀번호만 읽기
###############################################################################

resource "aws_iam_role" "db" {
  name               = "${var.name_prefix}-ec2-db"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "db_ssm" {
  role       = aws_iam_role.db.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "db_cw_agent" {
  role       = aws_iam_role.db.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/CloudWatchAgentServerPolicy"
}

data "aws_iam_policy_document" "db_secret_read" {
  statement {
    sid       = "ReadOwnDbSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.mysql_root.arn]
  }
}

resource "aws_iam_role_policy" "db_secret_read" {
  name   = "${var.name_prefix}-db-secret-read"
  role   = aws_iam_role.db.id
  policy = data.aws_iam_policy_document.db_secret_read.json
}

resource "aws_iam_instance_profile" "db" {
  name = "${var.name_prefix}-ec2-db"
  role = aws_iam_role.db.name
}

###############################################################################
# 대시보드 앱 역할 — 읽기 전용 + 실행 전용 분리
###############################################################################

resource "aws_iam_role" "dashboard" {
  name               = "${var.name_prefix}-ec2-dashboard"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "dashboard_ssm" {
  role       = aws_iam_role.dashboard.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "dashboard_cw_agent" {
  role       = aws_iam_role.dashboard.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/CloudWatchAgentServerPolicy"
}

data "aws_iam_policy_document" "dashboard_read_only" {
  statement {
    sid    = "ReadOnlyDetection"
    effect = "Allow"
    actions = [
      "securityhub:GetFindings",
      "securityhub:DescribeHub",
      "guardduty:ListDetectors",
      "guardduty:ListFindings",
      "guardduty:GetFindings",
      "inspector2:ListFindings",
      "inspector2:ListCoverage",
      "config:DescribeComplianceByConfigRule",
      "config:GetComplianceDetailsByConfigRule",
      "access-analyzer:ListAnalyzers",
      "access-analyzer:ListFindings",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:GetMetricData",
      "cloudwatch:DescribeAlarms",
      "ec2:DescribeInstances",
      "ec2:DescribeSecurityGroups",
    ]
    # 이 API들은 리소스 단위 제한을 지원하지 않아 "*" 를 씁니다.
    # 대신 전부 읽기 전용 동작만 골라 넣었습니다.
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "dashboard_read_only" {
  name   = "${var.name_prefix}-dashboard-readonly"
  role   = aws_iam_role.dashboard.id
  policy = data.aws_iam_policy_document.dashboard_read_only.json
}

data "aws_iam_policy_document" "dashboard_execute" {
  statement {
    sid    = "RunApprovedPlaybooksOnly"
    effect = "Allow"
    actions = [
      "ssm:StartAutomationExecution",
      "ssm:GetAutomationExecution",
    ]
    # ASR-* 로 시작하는 승인된 플레이북만 실행 가능.
    resources = [
      "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:automation-definition/${var.automation_document_prefix}*",
      "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:document/${var.automation_document_prefix}*",
      "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:automation-execution/*",
    ]
  }

  statement {
    sid       = "DescribeAutomationExecutions"
    effect    = "Allow"
    actions   = ["ssm:DescribeAutomationExecutions"]
    resources = ["*"]
  }

  # 대시보드가 SSM Automation 을 실행할 때 automation 역할을 넘겨야 하므로 PassRole 필요.
  # 넘길 수 있는 대상은 이 프로젝트의 SSM automation 역할 하나로 제한한다.
  statement {
    sid       = "PassAutomationRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.name_prefix}-ssm-automation"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ssm.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "dashboard_execute" {
  name   = "${var.name_prefix}-dashboard-execute"
  role   = aws_iam_role.dashboard.id
  policy = data.aws_iam_policy_document.dashboard_execute.json
}

resource "aws_iam_instance_profile" "dashboard" {
  name = "${var.name_prefix}-ec2-dashboard"
  role = aws_iam_role.dashboard.name
}
