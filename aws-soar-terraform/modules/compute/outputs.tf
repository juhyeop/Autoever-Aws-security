output "web_instance_id" {
  value = aws_instance.web.id
}

output "web_public_ip" {
  description = "ALB를 안 쓸 때 DVWA에 직접 접근할 주소."
  value       = aws_instance.web.public_ip
}

output "mysql_manual_instance_id" {
  value = aws_instance.mysql_manual.id
}

output "mysql_auto_instance_id" {
  value = aws_instance.mysql_auto.id
}

output "docker_instance_id" {
  value = aws_instance.docker.id
}

output "dashboard_instance_id" {
  value = aws_instance.dashboard.id
}

output "dashboard_private_ip" {
  value = aws_instance.dashboard.private_ip
}

output "all_instance_ids" {
  description = "CloudWatch 알람을 붙일 전체 인스턴스."
  value = {
    web          = aws_instance.web.id
    mysql_manual = aws_instance.mysql_manual.id
    mysql_auto   = aws_instance.mysql_auto.id
    docker       = aws_instance.docker.id
    dashboard    = aws_instance.dashboard.id
  }
}

output "alb_dns_name" {
  value = var.enable_alb ? aws_lb.web[0].dns_name : null
}

output "mysql_secret_arn" {
  value = aws_secretsmanager_secret.mysql_root.arn
}

output "dashboard_role_arn" {
  value = aws_iam_role.dashboard.arn
}
