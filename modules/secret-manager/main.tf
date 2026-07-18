resource "google_secret_manager_secret" "wordpress_db_password" {

  project = var.project_id

  secret_id = "wordpress-db-password"

  replication {

    auto {}

  }

}

resource "google_secret_manager_secret_version" "wordpress_db_password" {

  secret = google_secret_manager_secret.wordpress_db_password.id

  secret_data = var.db_password

}
