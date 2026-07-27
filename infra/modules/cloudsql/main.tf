resource "google_sql_database_instance" "mysql" {

  name                = var.instance_name
  database_version    = "MYSQL_8_0"
  region              = var.region
  deletion_protection = false #Make it true for prod or actual use

  settings {

    tier              = "db-custom-1-3840"
    availability_type = "ZONAL"

    disk_type       = "PD_SSD"
    disk_size       = 20
    disk_autoresize = true

    backup_configuration {
      enabled            = true
      binary_log_enabled = true
    }

    maintenance_window {
      day  = 7
      hour = 3
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_id
    }
  }
}

resource "google_sql_database" "wordpress" {

  name     = var.database_name
  instance = google_sql_database_instance.mysql.name
}

resource "google_sql_user" "wordpress" {

  instance = google_sql_database_instance.mysql.name
  name     = var.database_user

  password = random_password.db_password.result
}
