###############################################################################
# EventBridge 라우팅 — SOAR의 시작점
#
#   GuardDuty Finding            -> correlator Lambda
#   Security Hub Findings        -> asr_trigger Lambda  (MEDIUM 이상만)
#   SSM Automation 상태 변경      -> SNS (조치 결과 통보)
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

###############################################################################
# GuardDuty finding -> 상관분석
###############################################################################

resource "aws_cloudwatch_event_rule" "guardduty_finding" {
  name        = "${var.name_prefix}-guardduty-finding"
  description = "GuardDuty finding을 상관분석 Lambda로 보냅니다."

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    # 4.0 미만(LOW)은 시연 노이즈가 커서 제외합니다.
    detail = {
      severity = [{ numeric = [">=", 4.0] }]
    }
  })
}

resource "aws_cloudwatch_event_target" "guardduty_to_correlator" {
  rule      = aws_cloudwatch_event_rule.guardduty_finding.name
  target_id = "correlator"
  arn       = aws_lambda_function.correlator.arn
}

resource "aws_lambda_permission" "guardduty_to_correlator" {
  statement_id  = "AllowExecutionFromEventBridgeGuardDuty"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.correlator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.guardduty_finding.arn
}

###############################################################################
# Security Hub finding -> 자동조치 판단
###############################################################################

resource "aws_cloudwatch_event_rule" "securityhub_finding" {
  name        = "${var.name_prefix}-securityhub-finding"
  description = "Security Hub의 신규/갱신 finding을 자동조치 판단 Lambda로 보냅니다."

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = {
          Label = ["MEDIUM", "HIGH", "CRITICAL"]
        }
        RecordState = ["ACTIVE"]
        Workflow = {
          Status = ["NEW", "NOTIFIED"]
        }
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "securityhub_to_asr" {
  rule      = aws_cloudwatch_event_rule.securityhub_finding.name
  target_id = "asr-trigger"
  arn       = aws_lambda_function.asr_trigger.arn
}

resource "aws_lambda_permission" "securityhub_to_asr" {
  statement_id  = "AllowExecutionFromEventBridgeSecurityHub"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.asr_trigger.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.securityhub_finding.arn
}

###############################################################################
# 자동조치 실행 결과 -> SNS
#
# 대시보드의 "조치 관리" 탭과 별개로, 실행 성공/실패를 바로 메일로 받습니다.
###############################################################################

resource "aws_cloudwatch_event_rule" "automation_status" {
  name        = "${var.name_prefix}-automation-status"
  description = "SSM Automation 실행 완료/실패 알림"

  event_pattern = jsonencode({
    source      = ["aws.ssm"]
    detail-type = ["EC2 Automation Execution Status-change Notification"]
    detail = {
      Status = ["Success", "Failed", "TimedOut"]
    }
  })
}

resource "aws_cloudwatch_event_target" "automation_status_to_sns" {
  rule      = aws_cloudwatch_event_rule.automation_status.name
  target_id = "sns"
  arn       = aws_sns_topic.alerts.arn
}
