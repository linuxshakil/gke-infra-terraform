resource "kubernetes_service" "wordpress" {

  metadata {

    name      = "wordpress"
    namespace = kubernetes_namespace.wordpress.metadata[0].name

    annotations = {

      "cloud.google.com/neg" = jsonencode({
        ingress = true
      })

      "cloud.google.com/backend-config" = jsonencode({
        default = "wordpress-backend"
      })

    }

  }

  spec {

    selector = {
      app = "wordpress"
    }

    port {

      name        = "http"
      port        = 80
      target_port = 80

    }

    type = "ClusterIP"

  }

  ##############################################################
  # Ignore GKE-managed annotations
  #
  # GKE automatically adds annotations such as:
  # cloud.google.com/neg-status
  #
  # These are runtime-managed by GKE and should not be reconciled
  # by Terraform on every plan/apply.
  ##############################################################

  lifecycle {
    ignore_changes = [
      metadata[0].annotations
    ]
  }

}
