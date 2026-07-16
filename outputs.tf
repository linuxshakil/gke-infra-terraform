output "jenkins_url" {
  value = "http://${module.jenkins_vm.jenkins_vm_ip}:8080"
}
