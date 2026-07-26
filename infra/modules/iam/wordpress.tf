#########################################################
# WordPress Google Service Account
#########################################################

resource "google_service_account" "wordpress" {

  account_id   = "wordpress-gsa"
  display_name = "WordPress Service Account"

}

#########################################################
# Secret Manager Access
#########################################################

resource "google_project_iam_member" "wordpress_secret_accessor" {

  project = var.project_id

  role = "roles/secretmanager.secretAccessor"

  member = "serviceAccount:${google_service_account.wordpress.email}"

}

#########################################################
# Workload Identity
#########################################################

resource "google_service_account_iam_member" "wordpress_workload_identity" {

  service_account_id = google_service_account.wordpress.name

  role = "roles/iam.workloadIdentityUser"

  member = "serviceAccount:${var.project_id}.svc.id.goog[wordpress/wordpress-sa]"

}
