###############################################################################
# 탐지 · 분석 계층 (SIEM) — 설계문서 3장
#
#   GuardDuty            행위 기반 위협 탐지 (ML)
#   Inspector (v2)       EC2 / ECR CVE 스캔
#   AWS Config           리소스 설정 규정 준수
#   IAM Access Analyzer  리소스 정책의 외부 노출 분석
#   Security Hub         위 결과를 finding 으로 통합 (SIEM 허브)
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

###############################################################################
# GuardDuty
###############################################################################

resource "aws_guardduty_detector" "this" {
  count = var.enable_guardduty ? 1 : 0

  enable = true
  # 15분 주기가 시연에 가장 잘 맞습니다. (기본값은 6시간)
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  tags = {
    Name = "${var.name_prefix}-guardduty"
  }
}

# 추가 기능은 전부 별도 과금이라 변수로 받은 것만 켭니다.
# datasources 블록은 provider 6.x에서 deprecated 라 feature 리소스를 씁니다.
resource "aws_guardduty_detector_feature" "optional" {
  for_each = var.enable_guardduty ? {
    for f in var.guardduty_optional_features : f.name => f
  } : {}

  detector_id = aws_guardduty_detector.this[0].id
  name        = each.value.name
  status      = each.value.status
}

###############################################################################
# Inspector (v2)
###############################################################################

resource "aws_inspector2_enabler" "this" {
  count = var.enable_inspector ? 1 : 0

  account_ids    = [data.aws_caller_identity.current.account_id]
  resource_types = var.inspector_resource_types
}

###############################################################################
# IAM Access Analyzer — 외부 접근 분석기는 무료
###############################################################################

resource "aws_accessanalyzer_analyzer" "this" {
  count = var.enable_access_analyzer ? 1 : 0

  analyzer_name = "${var.name_prefix}-external-access"
  type          = "ACCOUNT"

  tags = {
    Name = "${var.name_prefix}-access-analyzer"
  }
}

###############################################################################
# Security Hub — SIEM 허브
#
# enable_default_standards = true 로 두면 AWS 기본 지정 표준(FSBP, CIS 등)이
# 자동으로 켜집니다. 그래서 aws_securityhub_standards_subscription 을 따로
# 선언하지 않습니다(중복 구독은 충돌이 납니다).
###############################################################################

resource "aws_securityhub_account" "this" {
  count = var.enable_security_hub ? 1 : 0

  enable_default_standards = true
  # 통합 제어 결과(consolidated control findings)를 켜면 같은 점검이 표준마다
  # 중복 생성되지 않아 대시보드 목록이 훨씬 깔끔해집니다.
  control_finding_generator = "SECURITY_CONTROL"
  auto_enable_controls      = true
}

# GuardDuty / Inspector / Access Analyzer 결과를 Security Hub로 흘려보냅니다.
# (계정에서 각 서비스를 켜면 기본 통합되지만, 명시해두면 의존 순서가 분명해집니다.)
resource "aws_securityhub_product_subscription" "guardduty" {
  count = var.enable_security_hub && var.enable_guardduty ? 1 : 0

  product_arn = "arn:${data.aws_partition.current.partition}:securityhub:${data.aws_region.current.region}::product/aws/guardduty"

  depends_on = [
    aws_securityhub_account.this,
    aws_guardduty_detector.this,
  ]
}

# Inspector v2 와 IAM Access Analyzer 는 Security Hub 에 "자동 통합"되는 서비스라
# aws_securityhub_product_subscription 으로 수동 구독할 수 없습니다.
# (product/aws/inspector-v2 구독 시도 → 404 ResourceNotFoundException)
# Security Hub 와 각 서비스를 켜두면 finding 이 알아서 흘러들어옵니다.
# 따라서 이 두 리소스는 삭제합니다. (GuardDuty 는 구독 가능해 위에 유지)
