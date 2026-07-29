variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "cluster_name" {
  type = string
}


variable "zone" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "machine_type" {
  type    = string
  default = "e2-medium"
}

variable "node_service_account" {
  type = string
}
