###############################################################################
# CloudTrail — 포렌식 조회용 (설계문서 3장)
#
# "이 finding / 조치가 왜 발생했는가"를 사람이 파고들 때 쓰는 근거 로그입니다.
# S3에 장기 보관하고 KMS로 암호화합니다.
###############################################################################

locals {
  trail_bucket_name = "${var.name_prefix}-cloudtrail-${data.aws_caller_identity.current.account_id}"
  trail_name        = "${var.name_prefix}-trail"
  trail_arn         = "arn:${data.aws_partition.current.partition}:cloudtrail:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:trail/${local.trail_name}"
}

###############################################################################
# KMS 키
###############################################################################

data "aws_iam_policy_document" "trail_kms" {
  # 계정 루트에 관리 권한 (이게 없으면 키를 다시 만질 수 없게 잠깁니다)
  statement {
    sid    = "EnableIAMUserPermissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudTrailEncrypt"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["kms:GenerateDataKey*"]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  statement {
    sid    = "AllowCloudTrailDescribeKey"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["kms:DescribeKey"]
    resources = ["*"]
  }

  # 저장된 로그를 계정 내에서 읽을 수 있게
  statement {
    sid    = "AllowAccountDecrypt"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:Decrypt", "kms:ReEncryptFrom"]
    resources = ["*"]
  }
}

resource "aws_kms_key" "trail" {
  count = var.enable_cloudtrail ? 1 : 0

  description             = "${var.name_prefix} CloudTrail log encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.trail_kms.json

  tags = {
    Name = "${var.name_prefix}-cloudtrail-kms"
  }
}

resource "aws_kms_alias" "trail" {
  count = var.enable_cloudtrail ? 1 : 0

  name          = "alias/${var.name_prefix}-cloudtrail"
  target_key_id = aws_kms_key.trail[0].key_id
}

###############################################################################
# S3 버킷
###############################################################################

resource "aws_s3_bucket" "trail" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket        = local.trail_bucket_name
  force_destroy = true # 시연용. 운영이라면 false로 두세요.

  tags = {
    Name = "${var.name_prefix}-cloudtrail"
  }
}

resource "aws_s3_bucket_public_access_block" "trail" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket                  = aws_s3_bucket.trail[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.trail[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.trail[0].arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "trail" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.trail[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

# 오래된 로그는 자동으로 지워 비용을 막습니다.
resource "aws_s3_bucket_lifecycle_configuration" "trail" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.trail[0].id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = 90
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

data "aws_iam_policy_document" "trail_bucket" {
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${local.trail_bucket_name}"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${local.trail_bucket_name}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = ["s3:*"]
    resources = [
      "arn:${data.aws_partition.current.partition}:s3:::${local.trail_bucket_name}",
      "arn:${data.aws_partition.current.partition}:s3:::${local.trail_bucket_name}/*",
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "trail" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.trail[0].id
  policy = data.aws_iam_policy_document.trail_bucket.json
}

###############################################################################
# 추적(trail)
###############################################################################

resource "aws_cloudtrail" "this" {
  count = var.enable_cloudtrail ? 1 : 0

  name           = local.trail_name
  s3_bucket_name = aws_s3_bucket.trail[0].id

  # 멀티 리전 + 글로벌 서비스 이벤트 — Security Hub / CIS 점검 항목이기도 합니다.
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
  kms_key_id                    = aws_kms_key.trail[0].arn

  tags = {
    Name = local.trail_name
  }

  depends_on = [aws_s3_bucket_policy.trail]
}
