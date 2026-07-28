output "namespace" {

  value = kubernetes_namespace.wordpress.metadata[0].name

}

output "service_name" {

  value = kubernetes_service.wordpress.metadata[0].name

}

output "deployment_name" {

  value = kubernetes_deployment.wordpress.metadata[0].name

}

output "ingress_name" {

  value = kubernetes_ingress_v1.wordpress.metadata[0].name

}
