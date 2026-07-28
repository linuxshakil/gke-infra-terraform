#############################################################
# Cloud SQL
#############################################################

output "cloudsql_private_ip" {
  value = module.cloudsql.private_ip
}

output "cloudsql_connection_name" {
  value = module.cloudsql.connection_name
}

output "database_password" {
  value     = module.cloudsql.database_password
  sensitive = true
}

#############################################################
# Secret Manager
#############################################################

output "secret_manager_secret" {
  value = module.secret_manager.secret_name
}

#############################################################
# Backup
#############################################################

output "backup_bucket_name" {
  value = module.backup.backup_bucket_name
}

output "backup_service_account" {
  value = module.backup.backup_service_account_email
}

#############################################################
# Artifact Registry
#############################################################

output "artifact_registry" {
  value = module.artifact_registry.repository_url
}

#############################################################
# Database
#############################################################

output "database_name" {
  value = var.database_name
}

output "database_user" {
  value = var.database_user
}

#############################################################
# IAM
#############################################################

output "node_service_account" {
  value = module.iam.node_sa_email
}
