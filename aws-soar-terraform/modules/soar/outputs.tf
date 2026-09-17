output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "correlator_function_name" {
  value = aws_lambda_function.correlator.function_name
}

output "asr_trigger_function_name" {
  value = aws_lambda_function.asr_trigger.function_name
}

output "automation_document_name" {
  description = "대시보드 config.py 의 ALLOWED_AUTOMATION_DOCUMENTS 에 넣을 문서 이름."
  value       = aws_ssm_document.revoke_open_ingress.name
}

output "automation_role_arn" {
  value = aws_iam_role.automation.arn
}

output "correlated_findings_table" {
  description = "대시보드가 상관분석 결과를 읽어갈 DynamoDB 테이블."
  value       = aws_dynamodb_table.correlated_findings.name
}

output "cloudwatch_dashboard_name" {
  value = aws_cloudwatch_dashboard.nms.dashboard_name
}
