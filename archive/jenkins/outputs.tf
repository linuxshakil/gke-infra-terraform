output "jenkins_namespace" {
  value = kubernetes_namespace.cicd.metadata[0].name
}

output "jenkins_sa_email" {
  value = google_service_account.jenkins_sa.email
}
