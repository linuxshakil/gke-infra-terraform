#output "jenkins_url" {
#  value = "http://${module.jenkins_vm.jenkins_vm_ip}:8080"
#}


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

output "wordpress_namespace" {
  value = module.wordpress.namespace
}

#output "wordpress_service_account" {
#  value = module.wordpress.service_account
#}
#
#output "wordpress_storage_class" {
#  value = module.wordpress.storage_class
#}


#output "wordpress_release" {
#  value = module.wordpress.helm_release
#}
