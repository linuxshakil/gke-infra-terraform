output "wordpress_gsa_email" {

  value = google_service_account.wordpress.email

}

output "external_secrets_gsa_email" {

  value = google_service_account.external_secrets.email

}

output "github_actions_gsa_email" {

  value = google_service_account.github_actions.email

}

output "jenkins_gsa_email" {

  value = google_service_account.jenkins.email

}

output "node_sa_email" {

  value = data.google_service_account.node_sa.email

}
