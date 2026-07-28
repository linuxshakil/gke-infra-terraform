output "wordpress_namespace" {

  value = module.wordpress.namespace

}

output "wordpress_service" {

  value = module.wordpress.service_name

}

output "wordpress_ingress" {

  value = module.wordpress.ingress_name

}
