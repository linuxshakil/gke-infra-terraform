output "jenkins_url" {
  value = "http://${module.jenkins_vm.jenkins_vm_ip}:8080"
}


output "cloudsql_private_ip" {

  value = module.cloudsql.private_ip

}

output "cloudsql_connection_name" {

  value = module.cloudsql.connection_name

}

output "database_password" {

  value = module.cloudsql.database_password

  sensitive = true

}

output "secret_manager_secret" {

  value = module.secret_manager.secret_name

}
