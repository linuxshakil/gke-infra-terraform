#########################################################
# Cloud SQL Backup Bucket Permissions
#########################################################

# Cloud SQL instance service account
# Used by Cloud SQL EXPORT/IMPORT operations

resource "google_storage_bucket_iam_member" "cloudsql_backup" {

  bucket = google_storage_bucket.sql_backup.name

  role = "roles/storage.objectAdmin"

  member = "serviceAccount:${var.cloudsql_service_account}"

}

#########################################################
# Backup Service Account Permissions
#########################################################

resource "google_project_iam_member" "backup_cloudsql_admin" {

  project = var.project_id

  role = "roles/cloudsql.admin"

  member = "serviceAccount:${google_service_account.backup.email}"

}

resource "google_project_iam_member" "backup_logging" {

  project = var.project_id

  role = "roles/logging.logWriter"

  member = "serviceAccount:${google_service_account.backup.email}"

}

resource "google_storage_bucket_iam_member" "backup_bucket_admin" {

  bucket = google_storage_bucket.sql_backup.name

  role = "roles/storage.objectAdmin"

  member = "serviceAccount:${google_service_account.backup.email}"

}
