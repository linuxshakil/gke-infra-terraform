variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "db_host" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_user" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "domain" {
  type = string
}

variable "gcp_service_account" {
  type = string
}
