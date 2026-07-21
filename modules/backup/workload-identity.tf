resource "google_service_account_iam_member" "backup_workload_identity" {

  service_account_id = google_service_account.backup.name

  role = "roles/iam.workloadIdentityUser"

  member = "serviceAccount:${var.project_id}.svc.id.goog[wordpress/cloudsql-backup]"

}
