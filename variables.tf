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

variable "zone" {
  type = string
}

variable "domain" {
  type = string
}

variable "db_instance_name" {
  type = string
}

variable "database_name" {
  type = string
}

variable "database_user" {
  type = string
}
