output "jenkins_vm_ip" {
  value = google_compute_instance.jenkins.network_interface[0].access_config[0].nat_ip
}

output "jenkins_sa_email" {
  value = google_service_account.jenkins_vm_sa.email
}
