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
