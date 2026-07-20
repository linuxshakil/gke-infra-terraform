variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "asia-south1"
}

variable "cluster_name" {
  type    = string
  default = "prod-gke-cluster"
}
variable "zone" {}

variable "domain" {}

variable "db_host" {}

variable "db_name" {}

variable "db_user" {}

variable "db_password" {
  sensitive = true
}
