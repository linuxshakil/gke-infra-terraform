##############################################################
# Cloud SQL Backup Bucket
##############################################################

resource "google_storage_bucket" "sql_backup" {

  name = "${var.project_id}-sql-backups"

  location = var.region

  project = var.project_id

  force_destroy = false

  uniform_bucket_level_access = true

  public_access_prevention = "enforced"

  versioning {

    enabled = true

  }

  lifecycle_rule {

    condition {

      age = 30

    }

    action {

      type = "Delete"

    }

  }

  labels = {

    purpose = "cloudsql-backup"

    managed-by = "terraform"

  }

}
