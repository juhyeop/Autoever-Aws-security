###############################################################################
# VPC + 멀티 서브넷 (설계문서 1장)
#
#   Public-Web   : ALB / 웹서버(DVWA)
#   Private-DB   : MySQL 수동 대응, MySQL 자동 대응
#   Private-App  : Docker 호스트, 대시보드 앱
#
# 한 AZ 안에서 용도별로만 나눕니다. ALB는 최소 2개 AZ를 요구하므로
# enable_alb=true 일 때만 두 번째 퍼블릭 서브넷을 추가로 만듭니다.
###############################################################################

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # ALB용 두 번째 AZ: 현재 AZ가 아닌 것 중 첫 번째.
  secondary_az = [
    for az in data.aws_availability_zones.available.names : az
    if az != var.availability_zone
  ][0]
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

###############################################################################
# 서브넷
###############################################################################

resource "aws_subnet" "public_web" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_web_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name_prefix}-public-web"
    Tier = "public-web"
  }
}

resource "aws_subnet" "public_secondary" {
  count = var.enable_alb ? 1 : 0

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.alb_secondary_subnet_cidr
  availability_zone       = local.secondary_az
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name_prefix}-public-alb-2nd"
    Tier = "public-web"
  }
}

resource "aws_subnet" "private_db" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_db_subnet_cidr
  availability_zone = var.availability_zone

  tags = {
    Name = "${var.name_prefix}-private-db"
    Tier = "private-db"
  }
}

resource "aws_subnet" "private_app" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_app_subnet_cidr
  availability_zone = var.availability_zone

  tags = {
    Name = "${var.name_prefix}-private-app"
    Tier = "private-app"
  }
}

###############################################################################
# NAT Gateway (선택) — 기본 off
###############################################################################

resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"

  tags = {
    Name = "${var.name_prefix}-nat-eip"
  }
}

resource "aws_nat_gateway" "this" {
  count = var.enable_nat_gateway ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public_web.id

  tags = {
    Name = "${var.name_prefix}-nat"
  }

  depends_on = [aws_internet_gateway.this]
}

###############################################################################
# 라우팅
###############################################################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.name_prefix}-rt-public"
  }
}

resource "aws_route_table_association" "public_web" {
  subnet_id      = aws_subnet.public_web.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_secondary" {
  count          = var.enable_alb ? 1 : 0
  subnet_id      = aws_subnet.public_secondary[0].id
  route_table_id = aws_route_table.public.id
}

# Private 라우트 테이블 2개(DB/App)를 따로 두어, 필요하면 한쪽만 NAT를 붙이거나
# 나중에 Network Firewall 엔드포인트로 경로를 틀 수 있게 해둡니다.
resource "aws_route_table" "private_db" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-rt-private-db"
  }
}

resource "aws_route_table" "private_app" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-rt-private-app"
  }
}

resource "aws_route" "private_db_nat" {
  count = var.enable_nat_gateway ? 1 : 0

  route_table_id         = aws_route_table.private_db.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}

resource "aws_route" "private_app_nat" {
  count = var.enable_nat_gateway ? 1 : 0

  route_table_id         = aws_route_table.private_app.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}

resource "aws_route_table_association" "private_db" {
  subnet_id      = aws_subnet.private_db.id
  route_table_id = aws_route_table.private_db.id
}

resource "aws_route_table_association" "private_app" {
  subnet_id      = aws_subnet.private_app.id
  route_table_id = aws_route_table.private_app.id
}

###############################################################################
# VPC Flow Logs — 설계문서 2장의 "MySQL 자동" 시나리오(포트 스캔) 근거 로그
###############################################################################

resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/aws/vpc/${var.name_prefix}/flow-logs"
  retention_in_days = 14 # 시연용이라 짧게. 보관 기간이 곧 비용입니다.
}

data "aws_iam_policy_document" "flow_logs_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  name               = "${var.name_prefix}-vpc-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json
}

data "aws_iam_policy_document" "flow_logs" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.flow_logs.arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  name   = "${var.name_prefix}-vpc-flow-logs"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs.json
}

resource "aws_flow_log" "this" {
  vpc_id                   = aws_vpc.this.id
  traffic_type             = "ALL"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow_logs.arn
  iam_role_arn             = aws_iam_role.flow_logs.arn
  max_aggregation_interval = 60

  tags = {
    Name = "${var.name_prefix}-flow-logs"
  }
}

###############################################################################
# NACL — 서브넷 단위 방어 (Security Group과의 이중 방어, 설계문서 1장)
#
# 상태 비저장(stateless)이라 응답 트래픽용 임시 포트를 반드시 같이 열어야 합니다.
# 시연 중 트래픽이 막히면 여기부터 확인하세요.
###############################################################################

resource "aws_network_acl" "private_db" {
  vpc_id     = aws_vpc.this.id
  subnet_ids = [aws_subnet.private_db.id]

  tags = {
    Name = "${var.name_prefix}-nacl-private-db"
  }
}

# 인바운드: VPC 내부에서 오는 트래픽만 허용
resource "aws_network_acl_rule" "db_in_vpc" {
  network_acl_id = aws_network_acl.private_db.id
  rule_number    = 100
  egress         = false
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = var.vpc_cidr
}

# 인바운드: 아웃바운드 통신의 응답(임시 포트)
resource "aws_network_acl_rule" "db_in_ephemeral" {
  network_acl_id = aws_network_acl.private_db.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "db_out_all" {
  network_acl_id = aws_network_acl.private_db.id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
}
