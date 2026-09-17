variable "name_prefix" {
  type = string
}

variable "enable_guardduty" {
  type = bool
}

variable "guardduty_optional_features" {
  type = list(object({
    name   = string
    status = optional(string, "ENABLED")
  }))
  default = []
}

variable "enable_inspector" {
  type = bool
}

variable "inspector_resource_types" {
  type = list(string)
}

variable "enable_config" {
  type = bool
}

variable "enable_security_hub" {
  type = bool
}

variable "enable_access_analyzer" {
  type = bool
}

variable "enable_cloudtrail" {
  type = bool
}
