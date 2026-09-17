output "guardduty_detector_id" {
  value = var.enable_guardduty ? aws_guardduty_detector.this[0].id : null
}

output "security_hub_enabled" {
  value = var.enable_security_hub
}

output "cloudtrail_bucket" {
  value = var.enable_cloudtrail ? aws_s3_bucket.trail[0].id : null
}

output "cloudtrail_arn" {
  value = var.enable_cloudtrail ? aws_cloudtrail.this[0].arn : null
}

output "config_bucket" {
  value = var.enable_config ? aws_s3_bucket.config[0].id : null
}

output "access_analyzer_arn" {
  value = var.enable_access_analyzer ? aws_accessanalyzer_analyzer.this[0].arn : null
}
