###############################################################################
# 기본 정보
###############################################################################

variable "project" {
  description = "모든 리소스 이름의 접두사."
  type        = string
  default     = "aws-secops"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.project))
    error_message = "project는 소문자/숫자/하이픈으로 3~21자여야 합니다 (S3 버킷 이름에도 쓰입니다)."
  }
}

variable "environment" {
  description = "환경 구분자 (lab / dev / demo 등)."
  type        = string
  default     = "lab"
}

variable "region" {
  description = "배포 리전."
  type        = string
  default     = "ap-northeast-2"
}

variable "availability_zone" {
  description = "단일 AZ 구성용 AZ. 설계상 한 AZ 안에서 용도별로만 서브넷을 나눕니다."
  type        = string
  default     = "ap-northeast-2a"
}

variable "tags" {
  description = "모든 리소스에 추가로 붙일 태그."
  type        = map(string)
  default     = {}
}

###############################################################################
# 네트워크
###############################################################################

variable "vpc_cidr" {
  description = "VPC CIDR."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_web_subnet_cidr" {
  description = "Public-Web 서브넷 (웹서버 / ALB)."
  type        = string
  default     = "10.0.0.0/24"
}

variable "private_db_subnet_cidr" {
  description = "Private-DB 서브넷 (MySQL 수동 / 자동)."
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_app_subnet_cidr" {
  description = "Private-App 서브넷 (Docker 호스트 / 대시보드 앱)."
  type        = string
  default     = "10.0.2.0/24"
}

variable "alb_secondary_subnet_cidr" {
  description = "ALB는 2개 AZ를 요구하므로, enable_alb=true일 때만 만드는 두 번째 퍼블릭 서브넷."
  type        = string
  default     = "10.0.3.0/24"
}

variable "admin_cidr" {
  description = <<-EOT
    SSH / 관리 접근을 허용할 CIDR. 팀 사무실이나 본인 공인 IP를 /32로 넣으세요.
    (예: "203.0.113.45/32"). 0.0.0.0/0 은 거부됩니다.
  EOT
  type        = string

  validation {
    condition     = var.admin_cidr != "0.0.0.0/0"
    error_message = "admin_cidr에 0.0.0.0/0 은 쓸 수 없습니다. 본인 공인 IP를 /32로 지정하세요."
  }

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0))
    error_message = "admin_cidr는 올바른 CIDR 표기여야 합니다 (예: 203.0.113.45/32)."
  }
}

###############################################################################
# 비용이 발생하는 리소스 토글 (기본 off)
###############################################################################

variable "enable_nat_gateway" {
  description = <<-EOT
    NAT Gateway 생성 여부. 시간당 + 데이터 처리 요금이 붙습니다(월 $35 내외).
    Private 서브넷 인스턴스 부트스트랩(패키지 설치, Secrets Manager 조회)에 필요하므로
    최초 apply 때만 true로 올렸다가, 부트스트랩이 끝나면 false로 되돌리는 걸 권장합니다.
    자세한 절차는 README의 "비용 통제" 참고.
  EOT
  type        = bool
  default     = false
}

variable "enable_alb" {
  description = "ALB + 두 번째 퍼블릭 서브넷 생성 여부. false면 웹서버 퍼블릭 IP로 직접 접근합니다."
  type        = bool
  default     = false
}

variable "enable_waf" {
  description = "WAFv2 WebACL 생성 및 ALB 연결 여부. enable_alb=true일 때만 동작합니다."
  type        = bool
  default     = false
}

###############################################################################
# 탐지 서비스 토글 (SIEM)
###############################################################################

variable "enable_guardduty" {
  description = "GuardDuty 활성화. 30일 무료 체험 후 분석량 기준 과금."
  type        = bool
  default     = true
}

variable "guardduty_optional_features" {
  description = <<-EOT
    추가로 켤 GuardDuty 기능. 전부 별도 과금이라 기본값은 빈 목록입니다.
    유효한 name: S3_DATA_EVENTS, EKS_AUDIT_LOGS, EBS_MALWARE_PROTECTION,
    RDS_LOGIN_EVENTS, EKS_RUNTIME_MONITORING, LAMBDA_NETWORK_LOGS,
    RUNTIME_MONITORING, AI_PROTECTION, AI_ANALYST
    (설계문서 3장의 "GuardDuty AI Protection" 발표 포인트를 시연하려면 AI_PROTECTION 추가)
  EOT
  type = list(object({
    name   = string
    status = optional(string, "ENABLED")
  }))
  default = []
}

variable "enable_inspector" {
  description = "Inspector(v2) 활성화. 15일 무료 체험 후 스캔 대상 수 기준 과금."
  type        = bool
  default     = true
}

variable "inspector_resource_types" {
  description = "Inspector 스캔 대상. 유효값: EC2, ECR, LAMBDA, LAMBDA_CODE, CODE_REPOSITORY."
  type        = list(string)
  default     = ["EC2", "ECR"]
}

variable "enable_config" {
  description = "AWS Config 활성화. 기록 항목 수 기준 과금이라 recording을 특정 리소스 타입으로 좁혀둡니다."
  type        = bool
  default     = true
}

variable "enable_security_hub" {
  description = "Security Hub 활성화 (SIEM 허브). 30일 무료 체험 후 과금."
  type        = bool
  default     = true
}

variable "enable_access_analyzer" {
  description = "IAM Access Analyzer(외부 접근 분석) 활성화. 외부 접근 분석기는 무료."
  type        = bool
  default     = true
}

variable "enable_cloudtrail" {
  description = "전용 CloudTrail 추적 생성 여부. 첫 번째 관리 이벤트 추적은 무료, S3 저장 비용만 발생."
  type        = bool
  default     = true
}

###############################################################################
# 컴퓨팅
###############################################################################

variable "instance_type" {
  description = "EC2 인스턴스 타입. 프리티어는 리전에 따라 t2.micro 또는 t3.micro."
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "EC2 키페어 이름. null이면 키페어 없이 생성되고 SSM Session Manager로만 접속합니다."
  type        = string
  default     = null
}

variable "root_volume_size" {
  description = "루트 EBS 볼륨 크기(GB). 프리티어 합계 30GB 한도를 넘지 않게 주의."
  type        = number
  default     = 8
}

###############################################################################
# SOAR / NMS
###############################################################################

variable "enable_auto_remediation" {
  description = <<-EOT
    자동 조치(SSM Automation) 실행 여부. false면 Lambda가 판단까지만 하고
    실제 실행 없이 SNS 알림만 보냅니다(시연 리허설용).
  EOT
  type        = bool
  default     = true
}

variable "alert_email" {
  description = <<-EOT
    CloudWatch 알람 / 자동조치 결과를 받을 이메일. null이면 구독을 만들지 않습니다.
    지정하면 apply 후 해당 주소로 오는 확인 메일을 눌러야 알림이 옵니다.
  EOT
  type        = string
  default     = null
}

variable "cpu_threshold" {
  description = "CPU 사용률 알람 임계치(%)."
  type        = number
  default     = 80
}

variable "mem_threshold" {
  description = "메모리 사용률 알람 임계치(%). CloudWatch Agent가 올리는 mem_used_percent 기준."
  type        = number
  default     = 80
}

variable "alarm_evaluation_periods" {
  description = "알람 평가 주기 수. 기본 5분(60초 x 5)으로 설계문서/실습과 맞춰둠."
  type        = number
  default     = 5
}
