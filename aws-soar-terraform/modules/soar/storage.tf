############################################
# DynamoDB — 상관분석 결과 / 조치 이력(Before-After)
# Lambda 가 EC2 위 대시보드 로컬 DB 에 직접 쓸 수 없으므로 여기에 적재하고,
# 대시보드는 boto3 로 읽습니다.
############################################

resource "aws_dynamodb_table" "correlated" {
  name         = var.correlated_findings_table
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "finding_id"

  attribute {
    name = "finding_id"
    type = "S"
  }

  tags = merge(var.tags, { Purpose = "guardduty-inspector-correlation" })
}

# 조치 이력 — 자동 조치는 대시보드를 거치지 않으므로 Lambda 가 여기에 직접 기록합니다.
# before_state / after_state 로 Before-After 비교(기획서 재검증 항목)를 보장합니다.
resource "aws_dynamodb_table" "actions" {
  name         = var.remediation_actions_table
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "action_id"
  range_key    = "created_at"

  attribute {
    name = "action_id"
    type = "S"
  }
  attribute {
    name = "created_at"
    type = "S"
  }

  tags = merge(var.tags, { Purpose = "remediation-before-after" })
}

############################################
# S3 — 수동 점검 결과(nmap / ZAP / Trivy) 적재
############################################

resource "aws_s3_bucket" "scan" {
  bucket        = var.scan_results_bucket
  force_destroy = true

  tags = merge(var.tags, { Purpose = "manual-scan-results" })
}

resource "aws_s3_bucket_public_access_block" "scan" {
  bucket = aws_s3_bucket.scan.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "scan" {
  bucket = aws_s3_bucket.scan.id
  versioning_configuration {
    status = "Enabled"
  }
}
