variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "asia-south1"
}

variable "bucket_name" {
  type = string
}

variable "github_repository" {
  type        = string
  description = "GitHub repository in owner/repo format"
}

variable "github_pool_name" {
  type    = string
  default = "github-pool"
}

variable "github_provider_name" {
  type    = string
  default = "github-provider"
}

variable "github_service_account_name" {
  type    = string
  default = "github-actions"
}
