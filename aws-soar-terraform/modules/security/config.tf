###############################################################################
# AWS Config — 리소스 설정 규정 준수
#
# 비용 주의: Config는 "기록한 설정 항목(configuration item) 수"로 과금됩니다.
# all_supported = true 로 두면 계정의 모든 리소스를 기록해서 금방 비싸지므로,
# 이 시나리오에 필요한 타입만 골라 기록합니다.
#
# 여기서 켜는 규칙들이 설계문서 2장 "MySQL 자동" 시나리오의 탐지 근거입니다.
###############################################################################

locals {
  config_bucket_name = "${var.name_prefix}-config-${data.aws_caller_identity.current.account_id}"

  # 시나리오에 필요한 리소스 타입만 기록
  config_resource_types = [
    "AWS::EC2::Instance",
    "AWS::EC2::SecurityGroup",
    "AWS::EC2::Volume",
    "AWS::S3::Bucket",
    "AWS::IAM::User",
    "AWS::IAM::Role",
    "AWS::IAM::Policy",
  ]
}

###############################################################################
# 기록 대상 저장소
###############################################################################

resource "aws_s3_bucket" "config" {
  count = var.enable_config ? 1 : 0

  bucket        = local.config_bucket_name
  force_destroy = true

  tags = {
    Name = "${var.name_prefix}-config"
  }
}

resource "aws_s3_bucket_public_access_block" "config" {
  count = var.enable_config ? 1 : 0

  bucket                  = aws_s3_bucket.config[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  count = var.enable_config ? 1 : 0

  bucket = aws_s3_bucket.config[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "config" {
  count = var.enable_config ? 1 : 0

  bucket = aws_s3_bucket.config[0].id

  rule {
    id     = "expire-old-config"
    status = "Enabled"
    filter {}
    expiration {
      days = 90
    }
  }
}

data "aws_iam_policy_document" "config_bucket" {
  statement {
    sid    = "AWSConfigBucketPermissionsCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl", "s3:ListBucket"]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${local.config_bucket_name}"]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "AWSConfigBucketDelivery"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${local.config_bucket_name}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "config" {
  count = var.enable_config ? 1 : 0

  bucket = aws_s3_bucket.config[0].id
  policy = data.aws_iam_policy_document.config_bucket.json
}

###############################################################################
# 기록기 (recorder) + 전송 채널 (delivery channel)
###############################################################################

data "aws_iam_policy_document" "config_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "config" {
  count = var.enable_config ? 1 : 0

  name               = "${var.name_prefix}-config"
  assume_role_policy = data.aws_iam_policy_document.config_assume.json
}

resource "aws_iam_role_policy_attachment" "config" {
  count = var.enable_config ? 1 : 0

  role       = aws_iam_role.config[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWS_ConfigRole"
}

# enable_config=false 일 때 aws_s3_bucket.config[0] 가 없으므로
# 이 data 소스에도 같은 count 를 걸어야 plan이 깨지지 않습니다.
data "aws_iam_policy_document" "config_s3_write" {
  count = var.enable_config ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.config[0].arn}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.config[0].arn]
  }
}

resource "aws_iam_role_policy" "config_s3_write" {
  count = var.enable_config ? 1 : 0

  name   = "${var.name_prefix}-config-s3"
  role   = aws_iam_role.config[0].id
  policy = data.aws_iam_policy_document.config_s3_write[0].json
}

resource "aws_config_configuration_recorder" "this" {
  count = var.enable_config ? 1 : 0

  name     = "${var.name_prefix}-recorder"
  role_arn = aws_iam_role.config[0].arn

  recording_group {
    all_supported                 = false
    include_global_resource_types = false
    resource_types                = local.config_resource_types
  }
}

resource "aws_config_delivery_channel" "this" {
  count = var.enable_config ? 1 : 0

  name           = "${var.name_prefix}-channel"
  s3_bucket_name = aws_s3_bucket.config[0].id

  depends_on = [
    aws_config_configuration_recorder.this,
    aws_s3_bucket_policy.config,
  ]
}

resource "aws_config_configuration_recorder_status" "this" {
  count = var.enable_config ? 1 : 0

  name       = aws_config_configuration_recorder.this[0].name
  is_enabled = true

  # 전송 채널이 먼저 있어야 기록기를 시작할 수 있습니다.
  depends_on = [aws_config_delivery_channel.this]
}

###############################################################################
# Config 규칙 — 침해사례 시나리오의 탐지 근거
###############################################################################

# "MySQL 자동" 시나리오: 3306 등 DB 포트가 0.0.0.0/0 으로 열렸는지
resource "aws_config_config_rule" "restricted_common_ports" {
  count = var.enable_config ? 1 : 0

  name        = "${var.name_prefix}-restricted-common-ports"
  description = "DB/관리 포트가 인터넷 전체에 열려 있는지 점검"

  source {
    owner             = "AWS"
    source_identifier = "RESTRICTED_INCOMING_TRAFFIC"
  }

  input_parameters = jsonencode({
    blockedPort1 = "3306" # MySQL — 자동조치 시나리오의 핵심
    blockedPort2 = "22"   # SSH
    blockedPort3 = "3389" # RDP
    blockedPort4 = "5432" # PostgreSQL
  })

  depends_on = [aws_config_configuration_recorder_status.this]
}

# 공개 S3 버킷 — 설계문서의 자동조치 대상 예시
resource "aws_config_config_rule" "s3_public_read" {
  count = var.enable_config ? 1 : 0

  name        = "${var.name_prefix}-s3-public-read-prohibited"
  description = "S3 버킷이 퍼블릭 읽기로 열려 있는지 점검"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }

  depends_on = [aws_config_configuration_recorder_status.this]
}

# 미사용 IAM 자격증명 — "노출된 액세스 키" 시나리오와 연결
resource "aws_config_config_rule" "iam_key_rotation" {
  count = var.enable_config ? 1 : 0

  name        = "${var.name_prefix}-access-keys-rotated"
  description = "IAM 액세스 키가 지정 기간 내에 교체되었는지 점검"

  source {
    owner             = "AWS"
    source_identifier = "ACCESS_KEYS_ROTATED"
  }

  input_parameters = jsonencode({
    maxAccessKeyAge = "90"
  })

  depends_on = [aws_config_configuration_recorder_status.this]
}

# EBS 암호화 여부
resource "aws_config_config_rule" "ebs_encrypted" {
  count = var.enable_config ? 1 : 0

  name        = "${var.name_prefix}-ebs-encrypted-volumes"
  description = "EBS 볼륨이 암호화되어 있는지 점검"

  source {
    owner             = "AWS"
    source_identifier = "ENCRYPTED_VOLUMES"
  }

  depends_on = [aws_config_configuration_recorder_status.this]
}
