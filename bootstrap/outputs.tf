############################################################
# Terraform Backend
############################################################

output "terraform_state_bucket" {

  description = "Terraform Remote State Bucket"

  value = google_storage_bucket.tf_state.name

}

############################################################
# GitHub Actions Service Account
############################################################

output "github_actions_service_account_email" {

  description = "GitHub Actions Service Account"

  value = google_service_account.github_actions.email

}

############################################################
# Workload Identity Pool
############################################################

output "workload_identity_pool_name" {

  description = "Workload Identity Pool"

  value = google_iam_workload_identity_pool.github.name

}

############################################################
# Workload Identity Provider
############################################################

output "workload_identity_provider" {

  description = "GitHub Workload Identity Provider"

  value = google_iam_workload_identity_pool_provider.github.name

}

############################################################
# GitHub Repository
############################################################

output "github_repository" {

  value = var.github_repository

}

############################################################
# GitHub Secrets
############################################################

output "github_secret_gcp_wif_provider" {

  description = "Copy this value into GitHub Secret GCP_WIF_PROVIDER"

  value = google_iam_workload_identity_pool_provider.github.name

}

output "github_secret_service_account" {

  description = "Copy this value into GitHub Secret GITHUB_ACTIONS_SA"

  value = google_service_account.github_actions.email

}

############################################################
# Backend Configuration
############################################################

output "backend_bucket" {

  value = google_storage_bucket.tf_state.name

}

output "backend_prefix" {

  value = "infra/state"

}
