###############################################################################
# Security Group (인스턴스 단위 방어)
#
# 규칙은 aws_vpc_security_group_*_rule 리소스로 하나씩 선언합니다.
# (aws_security_group 안에 inline ingress/egress를 같이 쓰면 서로 덮어써서 깨집니다.)
#
# 중요: "MySQL 자동 대응" 인스턴스의 3306을 0.0.0.0/0 으로 여는 규칙은 일부러
# 여기 넣지 않았습니다. 시연할 때 콘솔/CLI로 직접 열고(= 침해사례 재현),
# SOAR가 그 규칙을 지우는 걸 보여주는 게 시나리오이기 때문입니다.
# 테라폼이 만든 규칙을 SSM이 지우면 다음 apply 때 drift로 되살아납니다.
###############################################################################

locals {
  # ALB를 안 쓰면 웹서버가 직접 HTTP를 받습니다.
  web_http_source = var.enable_alb ? null : var.admin_cidr
}

###############################################################################
# ALB
###############################################################################

resource "aws_security_group" "alb" {
  count = var.enable_alb ? 1 : 0

  name        = "${var.name_prefix}-alb"
  description = "ALB ingress from admin CIDR only"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-alb"
  }
}

# DVWA는 의도적으로 취약한 앱이라 전 세계에 열지 않습니다. 팀 IP에서만 접근.
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  count = var.enable_alb ? 1 : 0

  security_group_id = aws_security_group.alb[0].id
  description       = "HTTP from admin CIDR"
  cidr_ipv4         = var.admin_cidr
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_all" {
  count = var.enable_alb ? 1 : 0

  security_group_id = aws_security_group.alb[0].id
  description       = "All egress"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

###############################################################################
# 웹서버 (DVWA)
###############################################################################

resource "aws_security_group" "web" {
  name        = "${var.name_prefix}-web"
  description = "DVWA web server"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-web"
  }
}

resource "aws_vpc_security_group_ingress_rule" "web_from_alb" {
  count = var.enable_alb ? 1 : 0

  security_group_id            = aws_security_group.web.id
  description                  = "HTTP from ALB"
  referenced_security_group_id = aws_security_group.alb[0].id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

resource "aws_vpc_security_group_ingress_rule" "web_from_admin" {
  count = var.enable_alb ? 0 : 1

  security_group_id = aws_security_group.web.id
  description       = "HTTP direct from admin CIDR (no ALB)"
  cidr_ipv4         = local.web_http_source
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "web_ssh" {
  security_group_id = aws_security_group.web.id
  description       = "SSH from admin CIDR"
  cidr_ipv4         = var.admin_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "web_all" {
  security_group_id = aws_security_group.web.id
  description       = "All egress"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

###############################################################################
# MySQL — 수동 대응 / 자동 대응 (2대)
###############################################################################

resource "aws_security_group" "mysql_manual" {
  name        = "${var.name_prefix}-mysql-manual"
  description = "MySQL (manual response scenario)"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-mysql-manual"
  }
}

resource "aws_security_group" "mysql_auto" {
  name        = "${var.name_prefix}-mysql-auto"
  description = "MySQL (auto remediation scenario)"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-mysql-auto"
    # SOAR Lambda가 이 태그를 보고 자동조치 대상인지 판단합니다.
    AutoRemediation = "enabled"
  }
}

resource "aws_vpc_security_group_ingress_rule" "mysql_manual_from_app" {
  security_group_id            = aws_security_group.mysql_manual.id
  description                  = "MySQL from app tier"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
}

resource "aws_vpc_security_group_ingress_rule" "mysql_manual_from_web" {
  security_group_id            = aws_security_group.mysql_manual.id
  description                  = "MySQL from web tier"
  referenced_security_group_id = aws_security_group.web.id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
}

resource "aws_vpc_security_group_ingress_rule" "mysql_manual_ssh" {
  security_group_id = aws_security_group.mysql_manual.id
  description       = "SSH from admin CIDR"
  cidr_ipv4         = var.admin_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "mysql_manual_all" {
  security_group_id = aws_security_group.mysql_manual.id
  description       = "All egress"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "mysql_auto_from_app" {
  security_group_id            = aws_security_group.mysql_auto.id
  description                  = "MySQL from app tier"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
}

resource "aws_vpc_security_group_ingress_rule" "mysql_auto_ssh" {
  security_group_id = aws_security_group.mysql_auto.id
  description       = "SSH from admin CIDR"
  cidr_ipv4         = var.admin_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "mysql_auto_all" {
  security_group_id = aws_security_group.mysql_auto.id
  description       = "All egress"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

###############################################################################
# App 티어 (Docker 호스트 + 대시보드 앱 공용)
###############################################################################

resource "aws_security_group" "app" {
  name        = "${var.name_prefix}-app"
  description = "Docker host and dashboard app"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-app"
  }
}

resource "aws_vpc_security_group_ingress_rule" "app_dashboard" {
  security_group_id = aws_security_group.app.id
  description       = "Flask dashboard from admin CIDR"
  cidr_ipv4         = var.admin_cidr
  ip_protocol       = "tcp"
  from_port         = 5000
  to_port           = 5000
}

resource "aws_vpc_security_group_ingress_rule" "app_ssh" {
  security_group_id = aws_security_group.app.id
  description       = "SSH from admin CIDR"
  cidr_ipv4         = var.admin_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "app_all" {
  security_group_id = aws_security_group.app.id
  description       = "All egress"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
