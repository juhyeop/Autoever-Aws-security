###############################################################################
# 원격 state (S3 backend + DynamoDB Lock)
#
# 닭이 먼저냐 달걀이 먼저냐 문제가 있어서 2단계로 씁니다.
#
#   1) bootstrap/ 을 먼저 apply 해서 state용 S3 버킷 + DynamoDB 잠금 테이블을 만듭니다.
#        cd bootstrap && terraform init && terraform apply
#      (bootstrap 자신의 state는 로컬 파일로 두고 git에 올리지 않습니다.)
#
#   2) bootstrap 출력값으로 아래 블록의 주석을 풀고 값을 채운 뒤,
#        terraform init -migrate-state
#      를 실행하면 로컬 state가 S3로 옮겨갑니다.
#
# 주석을 풀기 전까지는 로컬 state(terraform.tfstate)로 동작하므로,
# 혼자 테스트할 때는 그대로 두고 팀 작업을 시작할 때 전환하면 됩니다.
###############################################################################

# terraform {
#   backend "s3" {
#     bucket = "aws-secops-lab-tfstate-123456789012" # bootstrap 출력 state_bucket_name
#     key    = "soar-siem-nms/terraform.tfstate"
#     region = "ap-northeast-2"
#
#     # AWS provider 6.x / Terraform 1.6+ 에서는 DynamoDB 대신 S3 네이티브 잠금도 쓸 수 있지만,
#     # 설계문서에 맞춰 DynamoDB 잠금 테이블을 사용합니다.
#     dynamodb_table = "aws-secops-lab-tflock" # bootstrap 출력 lock_table_name
#     encrypt        = true
#   }
# }
