variable "project_id" {
  description = "Google Cloud Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
}

variable "cluster_name" {
  description = "GKE Cluster Name"
  type        = string
}

variable "private_service_range" {
  description = "Starting address for Service Networking range"
  type        = string
  default     = "10.40.0.0"
}

variable "private_service_prefix" {
  description = "Prefix length for Service Networking range"
  type        = number
  default     = 16
}
