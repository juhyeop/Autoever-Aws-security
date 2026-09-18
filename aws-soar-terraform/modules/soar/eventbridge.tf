############################################
# EventBridge — finding 을 Lambda 로 라우팅
#  ① GuardDuty finding      -> correlator  (상관분석)
#  ② GuardDuty finding      -> asr_trigger (IAM 키 노출 등 자동조치 판단)
#  ③ Security Hub finding    -> asr_trigger (SG 노출 등 자동조치 판단)
############################################

# ① GuardDuty -> correlator
resource "aws_cloudwatch_event_rule" "gd_to_correlator" {
  count = var.enable_guardduty ? 1 : 0

  name        = "${var.name_prefix}-gd-correlator"
  description = "GuardDuty findings to correlator Lambda"

  event_pattern = jsonencode({
    source        = ["aws.guardduty"]
    "detail-type" = ["GuardDuty Finding"]
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "gd_to_correlator" {
  count = var.enable_guardduty ? 1 : 0

  rule      = aws_cloudwatch_event_rule.gd_to_correlator[0].name
  target_id = "correlator"
  arn       = aws_lambda_function.correlator.arn
}

resource "aws_lambda_permission" "gd_to_correlator" {
  count = var.enable_guardduty ? 1 : 0

  statement_id  = "AllowGuardDutyCorrelator"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.correlator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.gd_to_correlator[0].arn
}

# ② GuardDuty -> asr_trigger (IAM 키 노출 계열)
resource "aws_cloudwatch_event_rule" "gd_to_asr" {
  count = var.enable_guardduty ? 1 : 0

  name        = "${var.name_prefix}-gd-asr"
  description = "GuardDuty credential/unauthorized findings to asr_trigger"

  event_pattern = jsonencode({
    source        = ["aws.guardduty"]
    "detail-type" = ["GuardDuty Finding"]
    detail = {
      type = [{ prefix = "UnauthorizedAccess:IAMUser" }, { prefix = "CredentialAccess:IAMUser" }, { prefix = "Discovery:IAMUser" }]
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "gd_to_asr" {
  count = var.enable_guardduty ? 1 : 0

  rule      = aws_cloudwatch_event_rule.gd_to_asr[0].name
  target_id = "asr-trigger"
  arn       = aws_lambda_function.asr_trigger.arn
}

resource "aws_lambda_permission" "gd_to_asr" {
  count = var.enable_guardduty ? 1 : 0

  statement_id  = "AllowGuardDutyAsr"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.asr_trigger.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.gd_to_asr[0].arn
}

# ③ Security Hub -> asr_trigger (SG 노출 등 설정 위반)
resource "aws_cloudwatch_event_rule" "sh_to_asr" {
  count = var.enable_security_hub ? 1 : 0

  name        = "${var.name_prefix}-sh-asr"
  description = "Security Hub findings to asr_trigger"

  event_pattern = jsonencode({
    source        = ["aws.securityhub"]
    "detail-type" = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Compliance  = { Status = ["FAILED", "WARNING"] }
        RecordState = ["ACTIVE"]
      }
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "sh_to_asr" {
  count = var.enable_security_hub ? 1 : 0

  rule      = aws_cloudwatch_event_rule.sh_to_asr[0].name
  target_id = "asr-trigger"
  arn       = aws_lambda_function.asr_trigger.arn
}

resource "aws_lambda_permission" "sh_to_asr" {
  count = var.enable_security_hub ? 1 : 0

  statement_id  = "AllowSecurityHubAsr"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.asr_trigger.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.sh_to_asr[0].arn
}
