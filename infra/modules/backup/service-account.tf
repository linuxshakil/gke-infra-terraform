#########################################################
# Backup Service Account
#########################################################

resource "google_service_account" "backup" {

  account_id = "cloudsql-backup-sa"

  display_name = "Cloud SQL Backup Service Account"

}
