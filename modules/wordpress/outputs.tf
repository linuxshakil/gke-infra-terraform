output "service_account" {

  value = kubernetes_service_account.wordpress.metadata[0].name

}
