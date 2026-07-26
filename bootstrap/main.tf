############################################################
# Enable Required APIs
############################################################

resource "google_project_service" "services" {

  for_each = toset([
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "sts.googleapis.com",
    "storage.googleapis.com"
  ])

  project = var.project_id
  service = each.key

  disable_on_destroy = false
}

############################################################
# Terraform Backend Bucket
############################################################

resource "google_storage_bucket" "tf_state" {

  name     = var.bucket_name
  project  = var.project_id
  location = var.region

  force_destroy = false

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {

    action {
      type = "Delete"
    }

    condition {
      num_newer_versions = 5
    }
  }

  depends_on = [
    google_project_service.services
  ]
}

############################################################
# GitHub Actions Service Account
############################################################

resource "google_service_account" "github_actions" {

  account_id   = var.github_service_account_name
  display_name = "GitHub Actions Service Account"

  depends_on = [
    google_project_service.services
  ]
}

############################################################
# Workload Identity Pool
############################################################

resource "google_iam_workload_identity_pool" "github" {

  workload_identity_pool_id = var.github_pool_name

  display_name = "GitHub Actions Pool"

  description = "OIDC pool for GitHub Actions"

  disabled = false

  depends_on = [
    google_project_service.services
  ]
}

############################################################
# Workload Identity Provider
############################################################

resource "google_iam_workload_identity_pool_provider" "github" {

  provider = google-beta

  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = var.github_provider_name

  display_name = "GitHub Provider"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  attribute_condition = "assertion.repository == \"${var.github_repository}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}


############################################################
# Allow GitHub Repository
############################################################

resource "google_service_account_iam_member" "github_actions_wif" {

  service_account_id = google_service_account.github_actions.name

  role = "roles/iam.workloadIdentityUser"

  member = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}
