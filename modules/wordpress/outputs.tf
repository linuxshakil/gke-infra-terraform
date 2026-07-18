output "namespace" {
  value = kubernetes_namespace.wordpress.metadata[0].name
}

output "service_account" {
  value = kubernetes_service_account.wordpress.metadata[0].name
}


output "helm_release" {
  value = helm_release.wordpress.name
}
