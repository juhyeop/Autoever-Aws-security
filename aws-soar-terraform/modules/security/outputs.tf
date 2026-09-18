output "guardduty_detector_id" {
  value = var.enable_guardduty ? aws_guardduty_detector.this[0].id : ""
}

output "security_hub_enabled" {
  value = var.enable_security_hub
}

output "config_rule_names" {
  value = var.enable_config ? [
    aws_config_config_rule.restricted_ssh[0].name,
    aws_config_config_rule.restricted_common_ports[0].name,
    aws_config_config_rule.iam_no_admin[0].name,
    aws_config_config_rule.cloudtrail_enabled[0].name,
  ] : []
}

output "access_analyzer_arn" {
  value = var.enable_access_analyzer ? aws_accessanalyzer_analyzer.this[0].arn : ""
}

output "cloudtrail_arn" {
  value = var.enable_cloudtrail ? aws_cloudtrail.this[0].arn : ""
}

output "cloudtrail_kms_key_arn" {
  value = var.enable_cloudtrail ? aws_kms_key.trail[0].arn : ""
}
