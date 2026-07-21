#########################################################
# External Secrets GSA
#########################################################

resource "google_service_account" "external_secrets" {

  account_id   = "external-secrets-gsa"
  display_name = "External Secrets GSA"

}

#########################################################
# Secret Manager Access
#########################################################

resource "google_project_iam_member" "external_secret_accessor" {

  project = var.project_id

  role = "roles/secretmanager.secretAccessor"

  member = "serviceAccount:${google_service_account.external_secrets.email}"

}

#########################################################
# Workload Identity
#########################################################

resource "google_service_account_iam_member" "external_secret_workload_identity" {

  service_account_id = google_service_account.external_secrets.name

  role = "roles/iam.workloadIdentityUser"

  member = "serviceAccount:${var.project_id}.svc.id.goog[external-secrets/external-secrets]"

}
