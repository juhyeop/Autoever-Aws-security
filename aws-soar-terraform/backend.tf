# 원격 state 를 쓰려면 이 파일을 backend.tf 로 복사하고 값을 채운 뒤
#   terraform init -migrate-state
# 를 실행하세요. 로컬 state 로 실습하면 이 파일은 무시합니다.
#
# terraform {
#   backend "s3" {
#     bucket         = "soar-sec-tfstate-<ACCOUNT_ID>"
#     key            = "soar-sec/terraform.tfstate"
#     region         = "ap-northeast-2"
#     dynamodb_table = "soar-sec-tflock"
#     encrypt        = true
#   }
# }
