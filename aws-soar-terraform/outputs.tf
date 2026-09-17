###############################################################################
# apply 후 시연에 바로 필요한 값들
###############################################################################

output "vpc_id" {
  value = module.network.vpc_id
}

output "dvwa_url" {
  description = "웹 취약점 시연 대상 주소. admin_cidr 에서만 접근됩니다."
  value       = var.enable_alb ? "http://${module.compute.alb_dns_name}" : "http://${module.compute.web_public_ip}"
}

output "dashboard_private_ip" {
  description = "Flask 대시보드 주소(사설). SSM 포트포워딩이나 Bastion으로 접근하세요."
  value       = "http://${module.compute.dashboard_private_ip}:5000"
}

output "instance_ids" {
  description = "시연용 인스턴스 목록."
  value       = module.compute.all_instance_ids
}

output "mysql_auto_security_group_id" {
  description = <<-EOT
    자동조치 시연의 핵심 대상.
    이 SG에 3306/0.0.0.0/0 규칙을 직접 넣으면(= 침해사례 재현)
    Config → Security Hub → EventBridge → Lambda → SSM Automation 순으로
    자동 회수되는 걸 볼 수 있습니다.
  EOT
  value       = module.network.mysql_auto_security_group_id
}

output "mysql_manual_security_group_id" {
  description = "같은 규칙을 넣어도 AutoRemediation 태그가 없어 수동 알림만 가는 대조군."
  value       = module.network.mysql_manual_security_group_id
}

output "mysql_secret_arn" {
  description = "MySQL root 비밀번호가 담긴 Secrets Manager 시크릿."
  value       = module.compute.mysql_secret_arn
}

output "sns_topic_arn" {
  value = module.soar.sns_topic_arn
}

output "asr_trigger_function_name" {
  description = "자동조치 판단 Lambda. demo/trigger-auto-remediation.sh 가 이 값을 씁니다."
  value       = module.soar.asr_trigger_function_name
}

output "correlator_function_name" {
  value = module.soar.correlator_function_name
}

output "region" {
  value = var.region
}

output "automation_document_name" {
  description = "대시보드 app/config.py 의 ALLOWED_AUTOMATION_DOCUMENTS 에 넣을 값."
  value       = module.soar.automation_document_name
}

output "automation_role_arn" {
  description = "대시보드가 SSM Automation 실행 시 넘길 automation 역할 ARN (자동대응 탭)."
  value       = module.soar.automation_role_arn
}

output "correlated_findings_table" {
  description = "GuardDuty x Inspector 상관분석 결과 테이블 (대시보드가 조회)."
  value       = module.soar.correlated_findings_table
}

output "cloudwatch_dashboard_url" {
  value = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${module.soar.cloudwatch_dashboard_name}"
}

output "cloudtrail_bucket" {
  value = module.security.cloudtrail_bucket
}

output "cost_warning" {
  description = "지금 켜져 있는 유료 리소스 요약."
  value = join(" | ", compact([
    var.enable_nat_gateway ? "NAT Gateway 켜짐(시간당 과금)" : null,
    var.enable_alb ? "ALB 켜짐(시간당 과금)" : null,
    var.enable_waf ? "WAF WebACL 켜짐(월 고정 + 요청당)" : null,
    var.enable_guardduty ? "GuardDuty 켜짐" : null,
    var.enable_inspector ? "Inspector 켜짐" : null,
    var.enable_config ? "Config 켜짐(기록 항목당)" : null,
    var.enable_security_hub ? "Security Hub 켜짐" : null,
  ]))
}
