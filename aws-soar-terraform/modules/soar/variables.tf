variable "name_prefix" { type = string }
variable "region" { type = string }
variable "account_id" { type = string }
variable "partition" { type = string }

variable "log_group_nginx" { type = string }
variable "log_group_mysql" { type = string }
variable "log_group_flowlogs" { type = string }
variable "log_retention_days" { type = number }

variable "correlated_findings_table" { type = string }
variable "remediation_actions_table" { type = string }
variable "scan_results_bucket" { type = string }

variable "enable_auto_remediation" { type = bool }
variable "auto_remediable_patterns" { type = list(string) }
variable "alert_email" { type = string }

variable "enable_guardduty" { type = bool }
variable "enable_security_hub" { type = bool }
variable "enable_config" { type = bool }
variable "enable_flow_logs" { type = bool }

variable "cpu_alarm_threshold" { type = number }
variable "memory_alarm_threshold" { type = number }
variable "mysql_auth_fail_threshold" { type = number }

variable "monitored_instances" { type = map(string) }
variable "db_security_group_id" {
  description = "db-manual-sg — SEC-06 수동 NACL 차단 시연 시 참고"
  type        = string
}
variable "public_nacl_id" { type = string }

variable "tags" {
  type    = map(string)
  default = {}
}
