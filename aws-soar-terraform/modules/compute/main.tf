###############################################################################
# EC2 5대 (설계문서 1~2장)
#
#   web           Public-Web   DVWA — 웹 취약점 시연 대상
#   mysql_manual  Private-DB   수동 대응 시나리오 (Hydra 무차별 대입)
#   mysql_auto    Private-DB   자동 대응 시나리오 (SG 3306 노출 → SOAR가 회수)
#   docker        Private-App  Trivy 이미지 스캔 대상
#   dashboard     Private-App  Flask 대시보드
###############################################################################

resource "aws_cloudwatch_log_group" "auth" {
  name              = "/${var.name_prefix}/os/secure"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "mysql" {
  name              = "/${var.name_prefix}/mysql/error"
  retention_in_days = 14
}

###############################################################################
# MySQL root 비밀번호 — Secrets Manager (설계문서 거버넌스 파트)
###############################################################################

resource "random_password" "mysql_root" {
  length  = 24
  special = true
  # MySQL 명령줄에서 문제를 일으키는 문자는 뺍니다.
  override_special = "!#%*-_=+"
}

resource "aws_secretsmanager_secret" "mysql_root" {
  name        = "${var.name_prefix}/mysql/root"
  description = "MySQL root password for the ${var.name_prefix} lab"

  # 시연 후 재생성할 일이 많아서 삭제 대기기간을 0으로 둡니다(즉시 삭제).
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "mysql_root" {
  secret_id = aws_secretsmanager_secret.mysql_root.id
  secret_string = jsonencode({
    username = "root"
    password = random_password.mysql_root.result
  })
}

###############################################################################
# user_data 조립
###############################################################################

locals {
  common_userdata = templatefile("${path.module}/userdata/common.sh", {
    log_group_auth = aws_cloudwatch_log_group.auth.name
  })

  web_userdata = base64encode(join("\n", [
    local.common_userdata,
    file("${path.module}/userdata/web.sh"),
  ]))

  mysql_manual_userdata = base64encode(join("\n", [
    local.common_userdata,
    templatefile("${path.module}/userdata/mysql.sh", {
      db_role         = "수동"
      secret_arn      = aws_secretsmanager_secret.mysql_root.arn
      region          = data.aws_region.current.region
      log_group_mysql = aws_cloudwatch_log_group.mysql.name
    }),
  ]))

  mysql_auto_userdata = base64encode(join("\n", [
    local.common_userdata,
    templatefile("${path.module}/userdata/mysql.sh", {
      db_role         = "자동"
      secret_arn      = aws_secretsmanager_secret.mysql_root.arn
      region          = data.aws_region.current.region
      log_group_mysql = aws_cloudwatch_log_group.mysql.name
    }),
  ]))

  docker_userdata = base64encode(join("\n", [
    local.common_userdata,
    file("${path.module}/userdata/docker.sh"),
  ]))

  dashboard_userdata = base64encode(join("\n", [
    local.common_userdata,
    templatefile("${path.module}/userdata/dashboard.sh", {
      region        = data.aws_region.current.region
      cpu_threshold = var.cpu_threshold
      mem_threshold = var.mem_threshold
    }),
  ]))
}

###############################################################################
# 인스턴스
###############################################################################

resource "aws_instance" "web" {
  ami                    = local.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.public_web_subnet_id
  vpc_security_group_ids = [var.web_security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.base.name
  key_name               = var.key_name
  user_data_base64       = local.web_userdata

  metadata_options {
    http_tokens   = "required" # IMDSv2 강제 — Security Hub / Config 점검 항목
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name     = "${var.name_prefix}-web-dvwa"
    Role     = "web"
    Scenario = "web"
  }
}

resource "aws_instance" "mysql_manual" {
  ami                    = local.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.private_db_subnet_id
  vpc_security_group_ids = [var.mysql_manual_security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.db.name
  key_name               = var.key_name
  user_data_base64       = local.mysql_manual_userdata

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name     = "${var.name_prefix}-mysql-manual"
    Role     = "mysql"
    Scenario = "mysql-manual"
    # AutoRemediation 태그를 일부러 붙이지 않습니다 → SOAR가 손대지 않음.
  }
}

resource "aws_instance" "mysql_auto" {
  ami                    = local.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.private_db_subnet_id
  vpc_security_group_ids = [var.mysql_auto_security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.db.name
  key_name               = var.key_name
  user_data_base64       = local.mysql_auto_userdata

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name     = "${var.name_prefix}-mysql-auto"
    Role     = "mysql"
    Scenario = "mysql-auto"
    # 이 태그가 있는 리소스만 SOAR Lambda가 자동조치합니다.
    AutoRemediation = "enabled"
  }
}

resource "aws_instance" "docker" {
  ami                    = local.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.private_app_subnet_id
  vpc_security_group_ids = [var.app_security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.base.name
  key_name               = var.key_name
  user_data_base64       = local.docker_userdata

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name     = "${var.name_prefix}-docker-host"
    Role     = "docker"
    Scenario = "docker"
  }
}

resource "aws_instance" "dashboard" {
  ami                    = local.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.private_app_subnet_id
  vpc_security_group_ids = [var.app_security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.dashboard.name
  key_name               = var.key_name
  user_data_base64       = local.dashboard_userdata

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${var.name_prefix}-dashboard"
    Role = "dashboard"
  }
}
