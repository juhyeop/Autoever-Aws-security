###############################################################################
# state 저장소 부트스트랩
#
# 이 디렉토리만 따로 apply 해서 원격 state용 S3 버킷과 DynamoDB 잠금 테이블을 만듭니다.
# 여기서 만든 값을 상위 디렉토리의 backend.tf 에 적어주세요.
#
#   terraform init
#   terraform apply -var="project=aws-secops" -var="environment=lab"
###############################################################################

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project   = var.project
      Purpose   = "terraform-state"
      ManagedBy = "terraform"
    }
  }
}

variable "project" {
  type    = string
  default = "aws-secops"
}

variable "environment" {
  type    = string
  default = "lab"
}

variable "region" {
  type    = string
  default = "ap-northeast-2"
}

data "aws_caller_identity" "current" {}

locals {
  # 버킷 이름은 전역 유일해야 하므로 계정 ID를 붙입니다.
  bucket_name = "${var.project}-${var.environment}-tfstate-${data.aws_caller_identity.current.account_id}"
  table_name  = "${var.project}-${var.environment}-tflock"
}

resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name

  # 실수로 destroy 되지 않도록. 정말 지울 때는 이 줄을 먼저 지우세요.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# state 버킷은 TLS 없이는 못 건드리게. (Security Hub / Config 점검 항목이기도 합니다.)
resource "aws_s3_bucket_policy" "state_tls_only" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state_tls_only.json
}

data "aws_iam_policy_document" "state_tls_only" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_dynamodb_table" "lock" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST" # 잠금 테이블은 요청이 거의 없어서 온디맨드가 제일 쌉니다.
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }
}

output "state_bucket_name" {
  description = "backend.tf 의 bucket 에 넣을 값."
  value       = aws_s3_bucket.state.id
}

output "lock_table_name" {
  description = "backend.tf 의 dynamodb_table 에 넣을 값."
  value       = aws_dynamodb_table.lock.name
}
