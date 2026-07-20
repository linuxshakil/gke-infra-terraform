resource "kubernetes_service_account" "wordpress" {
  metadata {
    name      = "wordpress-sa"
    namespace = kubernetes_namespace.wordpress.metadata[0].name
  }
}
