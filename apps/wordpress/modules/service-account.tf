resource "kubernetes_service_account" "wordpress" {
  metadata {
    name      = "wordpress-sa"
    namespace = kubernetes_namespace.wordpress.metadata[0].name

    annotations = {
      "iam.gke.io/gcp-service-account" = var.gcp_service_account
    }
  }
}
