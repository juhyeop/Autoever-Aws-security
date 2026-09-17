data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

# Amazon Linux 2023 최신 AMI. AMI ID를 하드코딩하면 리전이 바뀌거나
# 시간이 지났을 때 깨지므로 SSM 퍼블릭 파라미터로 조회합니다.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
}

locals {
  ami_id = data.aws_ssm_parameter.al2023.value
}
