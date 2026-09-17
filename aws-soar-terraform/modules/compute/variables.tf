variable "name_prefix" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "key_name" {
  type    = string
  default = null
}

variable "root_volume_size" {
  type = number
}

variable "public_web_subnet_id" {
  type = string
}

variable "private_db_subnet_id" {
  type = string
}

variable "private_app_subnet_id" {
  type = string
}

variable "alb_subnet_ids" {
  type = list(string)
}

variable "web_security_group_id" {
  type = string
}

variable "mysql_manual_security_group_id" {
  type = string
}

variable "mysql_auto_security_group_id" {
  type = string
}

variable "app_security_group_id" {
  type = string
}

variable "alb_security_group_id" {
  type    = string
  default = null
}

variable "vpc_id" {
  type = string
}

variable "enable_alb" {
  type = bool
}

variable "enable_waf" {
  type = bool
}

variable "cpu_threshold" {
  type = number
}

variable "mem_threshold" {
  type = number
}

variable "automation_document_prefix" {
  description = "대시보드가 실행할 수 있는 SSM Automation 문서 이름 접두사 (최소권한 범위)."
  type        = string
  default     = "ASR-"
}
