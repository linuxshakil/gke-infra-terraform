output "secret_name" {

  value = google_secret_manager_secret.wordpress_db_password.secret_id

}

output "secret_id" {

  value = google_secret_manager_secret.wordpress_db_password.id

}
