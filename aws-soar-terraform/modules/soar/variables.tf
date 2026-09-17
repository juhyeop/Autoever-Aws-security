variable "name_prefix" {
  type = string
}

variable "monitored_instance_ids" {
  description = "CPU/Mem 알람을 붙일 인스턴스. key는 알람 이름에 쓰입니다."
  type        = map(string)
}

variable "enable_auto_remediation" {
  description = "false면 Lambda가 판단만 하고 SSM 실행은 하지 않습니다(dry-run)."
  type        = bool
  default     = true
}

variable "reimport_to_security_hub" {
  description = "상관분석 결과를 Security Hub에 커스텀 finding으로 재게시할지 여부."
  type        = bool
  default     = true
}

variable "automation_document_prefix" {
  description = "SSM Automation 문서 이름 접두사. 최소권한 IAM 정책의 범위와 맞춰야 합니다."
  type        = string
  default     = "ASR-"
}

variable "alert_email" {
  type    = string
  default = null
}

variable "cpu_threshold" {
  type = number
}

variable "mem_threshold" {
  type = number
}

variable "alarm_evaluation_periods" {
  type = number
}
