resource "google_project_iam_member" "cloudsql_client" {

  project = var.project_id

  role = "roles/cloudsql.client"

  member = "serviceAccount:${var.gcp_service_account}"

}


#Workload Identity Binding

resource "google_service_account_iam_member" "workload_identity" {

  service_account_id = "projects/${var.project_id}/serviceAccounts/${var.gcp_service_account}"

  role = "roles/iam.workloadIdentityUser"

  member = "serviceAccount:${var.project_id}.svc.id.goog[wordpress/wordpress-sa]"

}
