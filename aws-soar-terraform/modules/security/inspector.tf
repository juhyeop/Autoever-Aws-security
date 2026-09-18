############################################
# Inspector2 — EC2 / ECR 이미지 CVE 스캔 (SEC-04)
############################################

resource "aws_inspector2_enabler" "this" {
  count = var.enable_inspector2 ? 1 : 0

  account_ids    = [var.account_id]
  resource_types = ["EC2", "ECR"]
}
