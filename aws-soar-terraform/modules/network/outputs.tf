output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "public_web_subnet_id" {
  value = aws_subnet.public_web.id
}

output "alb_subnet_ids" {
  description = "ALB용 서브넷 2개 (enable_alb=false면 빈 목록)."
  value       = var.enable_alb ? [aws_subnet.public_web.id, aws_subnet.public_secondary[0].id] : []
}

output "private_db_subnet_id" {
  value = aws_subnet.private_db.id
}

output "private_app_subnet_id" {
  value = aws_subnet.private_app.id
}

output "alb_security_group_id" {
  value = var.enable_alb ? aws_security_group.alb[0].id : null
}

output "web_security_group_id" {
  value = aws_security_group.web.id
}

output "mysql_manual_security_group_id" {
  value = aws_security_group.mysql_manual.id
}

output "mysql_auto_security_group_id" {
  description = "자동조치 시연에서 3306을 열었다가 SOAR가 닫는 대상 SG."
  value       = aws_security_group.mysql_auto.id
}

output "app_security_group_id" {
  value = aws_security_group.app.id
}

output "flow_log_group_name" {
  value = aws_cloudwatch_log_group.flow_logs.name
}
