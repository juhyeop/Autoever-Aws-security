###############################################################################
# Lambda 2개 (설계문서 4장)
#
#   correlator   GuardDuty finding + Inspector CVE 를 합쳐 DynamoDB에 적재
#   asr_trigger  Security Hub finding을 보고 자동조치 여부 판단 → SSM 실행
###############################################################################

data "archive_file" "correlator" {
  type        = "zip"
  source_dir  = "${path.module}/functions/correlator"
  output_path = "${path.module}/.build/correlator.zip"
}

data "archive_file" "asr_trigger" {
  type        = "zip"
  source_dir  = "${path.module}/functions/asr_trigger"
  output_path = "${path.module}/.build/asr_trigger.zip"
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

###############################################################################
# 상관분석 Lambda
###############################################################################

resource "aws_iam_role" "correlator" {
  name               = "${var.name_prefix}-lambda-correlator"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "correlator" {
  statement {
    sid       = "Logs"
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:${data.aws_partition.current.partition}:logs:*:*:*"]
  }

  statement {
    sid    = "ReadDetections"
    effect = "Allow"
    actions = [
      "guardduty:GetFindings",
      "inspector2:ListFindings",
      "securityhub:BatchImportFindings",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "WriteCorrelatedFindings"
    effect = "Allow"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:GetItem",
    ]
    resources = [aws_dynamodb_table.correlated_findings.arn]
  }

  statement {
    sid       = "Notify"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }
}

resource "aws_iam_role_policy" "correlator" {
  name   = "${var.name_prefix}-lambda-correlator"
  role   = aws_iam_role.correlator.id
  policy = data.aws_iam_policy_document.correlator.json
}

# 로그 그룹을 명시적으로 만들어 보관 기간을 제어합니다.
# (안 만들면 Lambda가 자동 생성하고 보관 기간이 "무기한"이 됩니다.)
resource "aws_cloudwatch_log_group" "correlator" {
  name              = "/aws/lambda/${var.name_prefix}-correlator"
  retention_in_days = 14
}

resource "aws_lambda_function" "correlator" {
  function_name = "${var.name_prefix}-correlator"
  role          = aws_iam_role.correlator.arn
  handler       = "index.handler"
  runtime       = "python3.12"
  timeout       = 60
  memory_size   = 256

  filename         = data.archive_file.correlator.output_path
  source_code_hash = data.archive_file.correlator.output_base64sha256

  environment {
    variables = {
      FINDINGS_TABLE           = aws_dynamodb_table.correlated_findings.name
      SNS_TOPIC_ARN            = aws_sns_topic.alerts.arn
      REIMPORT_TO_SECURITY_HUB = tostring(var.reimport_to_security_hub)
    }
  }

  depends_on = [aws_cloudwatch_log_group.correlator]

  tags = {
    Name = "${var.name_prefix}-correlator"
  }
}

###############################################################################
# 자동조치 판단 Lambda
###############################################################################

resource "aws_iam_role" "asr_trigger" {
  name               = "${var.name_prefix}-lambda-asr-trigger"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "asr_trigger" {
  statement {
    sid       = "Logs"
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:${data.aws_partition.current.partition}:logs:*:*:*"]
  }

  statement {
    sid       = "InspectTargets"
    effect    = "Allow"
    actions   = ["ec2:DescribeSecurityGroups", "ec2:DescribeInstances"]
    resources = ["*"]
  }

  # 승인된 ASR-* 플레이북만 실행할 수 있습니다.
  statement {
    sid     = "RunApprovedPlaybooksOnly"
    effect  = "Allow"
    actions = ["ssm:StartAutomationExecution"]
    resources = [
      "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:automation-definition/${var.automation_document_prefix}*",
      "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:document/${var.automation_document_prefix}*",
    ]
  }

  # Automation이 쓸 역할을 넘겨줄 수 있어야 합니다(딱 그 역할만).
  statement {
    sid       = "PassAutomationRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.automation.arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ssm.amazonaws.com"]
    }
  }

  statement {
    sid       = "Notify"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }
}

resource "aws_iam_role_policy" "asr_trigger" {
  name   = "${var.name_prefix}-lambda-asr-trigger"
  role   = aws_iam_role.asr_trigger.id
  policy = data.aws_iam_policy_document.asr_trigger.json
}

resource "aws_cloudwatch_log_group" "asr_trigger" {
  name              = "/aws/lambda/${var.name_prefix}-asr-trigger"
  retention_in_days = 14
}

resource "aws_lambda_function" "asr_trigger" {
  function_name = "${var.name_prefix}-asr-trigger"
  role          = aws_iam_role.asr_trigger.arn
  handler       = "index.handler"
  runtime       = "python3.12"
  timeout       = 60
  memory_size   = 256

  filename         = data.archive_file.asr_trigger.output_path
  source_code_hash = data.archive_file.asr_trigger.output_base64sha256

  environment {
    variables = {
      AUTOMATION_DOCUMENT      = aws_ssm_document.revoke_open_ingress.name
      AUTOMATION_ROLE_ARN      = aws_iam_role.automation.arn
      SNS_TOPIC_ARN            = aws_sns_topic.alerts.arn
      AUTO_REMEDIATION_ENABLED = tostring(var.enable_auto_remediation)
      REQUIRED_TAG_KEY         = "AutoRemediation"
      REQUIRED_TAG_VALUE       = "enabled"
    }
  }

  depends_on = [aws_cloudwatch_log_group.asr_trigger]

  tags = {
    Name = "${var.name_prefix}-asr-trigger"
  }
}

###############################################################################
# 상관분석 결과 저장소 — 대시보드가 boto3로 읽습니다.
###############################################################################

resource "aws_dynamodb_table" "correlated_findings" {
  name         = "${var.name_prefix}-correlated-findings"
  billing_mode = "PAY_PER_REQUEST" # 시연 트래픽에는 온디맨드가 제일 쌉니다.
  hash_key     = "finding_id"

  attribute {
    name = "finding_id"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  point_in_time_recovery {
    enabled = false # 시연용. 운영이면 켜세요.
  }

  tags = {
    Name = "${var.name_prefix}-correlated-findings"
  }
}
