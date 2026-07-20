variable "db_host" {}

variable "db_name" {}

variable "db_user" {}

variable "db_password" {
  sensitive = true
}

variable "domain" {}

variable "service_account" {
  default = "wordpress-sa"
}
