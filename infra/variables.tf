variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "zone" {
  type = string
}

variable "cluster_name" {
  type    = string
  default = "prod-gke-cluster"
}

variable "machine_type" {
  type    = string
  default = "e2-medium"
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
