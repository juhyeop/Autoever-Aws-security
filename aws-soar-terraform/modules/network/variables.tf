variable "name_prefix" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "availability_zone" {
  type = string
}

variable "public_web_subnet_cidr" {
  type = string
}

variable "private_db_subnet_cidr" {
  type = string
}

variable "private_app_subnet_cidr" {
  type = string
}

variable "alb_secondary_subnet_cidr" {
  type = string
}

variable "admin_cidr" {
  type = string
}

variable "enable_nat_gateway" {
  type = bool
}

variable "enable_alb" {
  type = bool
}
