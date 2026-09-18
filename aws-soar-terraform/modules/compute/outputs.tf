output "docker_host_instance_id" { value = aws_instance.docker_host.id }
output "docker_host_private_ip" { value = aws_instance.docker_host.private_ip }

output "db_instance_id" { value = aws_instance.db.id }
output "db_private_ip" { value = aws_instance.db.private_ip }

output "dashboard_instance_id" { value = aws_instance.dashboard.id }
output "dashboard_private_ip" { value = aws_instance.dashboard.private_ip }

output "web_dvwa_instance_id" {
  value = var.enable_dvwa_instance ? aws_instance.web_dvwa[0].id : ""
}

output "web_dvwa_public_ip" {
  value = var.enable_dvwa_instance ? aws_instance.web_dvwa[0].public_ip : ""
}

output "attacker_instance_id" {
  value = var.enable_attacker_instance ? aws_instance.attacker[0].id : ""
}

# CloudWatch 알람이 붙을 인스턴스 목록 (soar 모듈이 사용)
output "monitored_instances" {
  description = "알람 대상 인스턴스 { 이름 => 인스턴스 ID }"
  value = merge(
    {
      "docker-host" = aws_instance.docker_host.id
      "db"          = aws_instance.db.id
      "dashboard"   = aws_instance.dashboard.id
    },
    var.enable_dvwa_instance ? { "web-dvwa" = aws_instance.web_dvwa[0].id } : {},
    var.enable_attacker_instance ? { "attacker" = aws_instance.attacker[0].id } : {},
  )
}

output "alb_dns_name" {
  value = var.enable_alb ? aws_lb.main[0].dns_name : ""
}

output "alb_arn" {
  value = var.enable_alb ? aws_lb.main[0].arn : ""
}

output "web_acl_arn" {
  value = var.enable_alb && var.enable_waf ? aws_wafv2_web_acl.main[0].arn : ""
}

output "ecr_repository_url" { value = aws_ecr_repository.app.repository_url }
output "ecr_repository_name" { value = aws_ecr_repository.app.name }

output "db_secret_name" { value = aws_secretsmanager_secret.db.name }
output "db_secret_arn" { value = aws_secretsmanager_secret.db.arn }

output "dashboard_role_name" { value = aws_iam_role.dashboard.name }
output "dashboard_role_arn" { value = aws_iam_role.dashboard.arn }
