variable "project_id" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "region" {
  type = string
}

variable "private_service_range" {
  type    = string
  default = "10.40.0.0"
}

variable "private_service_prefix" {
  type    = number
  default = 16
}
