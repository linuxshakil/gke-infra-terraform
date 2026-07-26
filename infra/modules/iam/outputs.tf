output "wordpress_gsa_email" {
  description = "WordPress GSA Email"
  value       = google_service_account.wordpress.email
}

output "external_secrets_gsa_email" {
  description = "External Secrets GSA Email"
  value       = google_service_account.external_secrets.email
}

output "github_actions_gsa_email" {
  description = "GitHub Actions GSA Email"
  value       = google_service_account.github_actions.email
}

output "jenkins_gsa_email" {
  description = "Jenkins GSA Email"
  value       = google_service_account.jenkins.email
}

output "node_sa_email" {
  description = "GKE Node Pool Service Account"
  value       = google_service_account.node_sa.email
}
