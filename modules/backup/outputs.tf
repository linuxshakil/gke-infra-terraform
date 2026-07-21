output "backup_bucket_name" {

  value = google_storage_bucket.sql_backup.name

}

output "backup_service_account_email" {

  value = google_service_account.backup.email

}
