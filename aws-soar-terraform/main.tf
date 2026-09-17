###############################################################################
# AWS 기반 SOAR / SIEM / NMS 보안 관제 — 루트 모듈
#
# 설계문서: claude/soar-siem-nms-dashboard-architecture.md (v7)
#
#   network   VPC · 3개 서브넷 · SG · NACL · VPC Flow Logs
#   compute   EC2 5대 (DVWA / MySQL 수동·자동 / Docker / 대시보드) · ALB+WAF(옵션)
#   security  GuardDuty · Inspector · Config · Access Analyzer · Security Hub · CloudTrail
#   soar      EventBridge · Lambda 2개 · SSM Automation · SNS · CloudWatch 알람
###############################################################################

module "network" {
  source = "./modules/network"

  name_prefix               = local.name_prefix
  vpc_cidr                  = var.vpc_cidr
  availability_zone         = var.availability_zone
  public_web_subnet_cidr    = var.public_web_subnet_cidr
  private_db_subnet_cidr    = var.private_db_subnet_cidr
  private_app_subnet_cidr   = var.private_app_subnet_cidr
  alb_secondary_subnet_cidr = var.alb_secondary_subnet_cidr
  admin_cidr                = var.admin_cidr
  enable_nat_gateway        = var.enable_nat_gateway
  enable_alb                = var.enable_alb
}

module "compute" {
  source = "./modules/compute"

  name_prefix      = local.name_prefix
  instance_type    = var.instance_type
  key_name         = var.key_name
  root_volume_size = var.root_volume_size

  vpc_id                = module.network.vpc_id
  public_web_subnet_id  = module.network.public_web_subnet_id
  private_db_subnet_id  = module.network.private_db_subnet_id
  private_app_subnet_id = module.network.private_app_subnet_id
  alb_subnet_ids        = module.network.alb_subnet_ids

  web_security_group_id          = module.network.web_security_group_id
  mysql_manual_security_group_id = module.network.mysql_manual_security_group_id
  mysql_auto_security_group_id   = module.network.mysql_auto_security_group_id
  app_security_group_id          = module.network.app_security_group_id
  alb_security_group_id          = module.network.alb_security_group_id

  enable_alb = var.enable_alb
  enable_waf = var.enable_waf

  cpu_threshold = var.cpu_threshold
  mem_threshold = var.mem_threshold
}

module "security" {
  source = "./modules/security"

  name_prefix = local.name_prefix

  enable_guardduty            = var.enable_guardduty
  guardduty_optional_features = var.guardduty_optional_features
  enable_inspector            = var.enable_inspector
  inspector_resource_types    = var.inspector_resource_types
  enable_config               = var.enable_config
  enable_security_hub         = var.enable_security_hub
  enable_access_analyzer      = var.enable_access_analyzer
  enable_cloudtrail           = var.enable_cloudtrail
}

module "soar" {
  source = "./modules/soar"

  name_prefix              = local.name_prefix
  monitored_instance_ids   = module.compute.all_instance_ids
  enable_auto_remediation  = var.enable_auto_remediation
  alert_email              = var.alert_email
  cpu_threshold            = var.cpu_threshold
  mem_threshold            = var.mem_threshold
  alarm_evaluation_periods = var.alarm_evaluation_periods

  # SOAR는 Security Hub가 켜져 있어야 finding을 받습니다.
  depends_on = [module.security]
}
