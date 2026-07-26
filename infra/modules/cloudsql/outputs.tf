output "instance_name" {
  value = google_sql_database_instance.mysql.name
}

output "private_ip" {
  value = google_sql_database_instance.mysql.private_ip_address
}

output "connection_name" {
  value = google_sql_database_instance.mysql.connection_name
}

output "database_name" {
  value = google_sql_database.wordpress.name
}

output "database_user" {
  value = google_sql_user.wordpress.name
}

output "database_password" {
  value     = random_password.db_password.result
  sensitive = true
}
##############################################################
# Cloud SQL Instance Service Account
##############################################################

output "service_account_email" {

  value = google_sql_database_instance.mysql.service_account_email_address

}
