resource "kubernetes_ingress_v1" "wordpress" {

  metadata {

    name      = "wordpress"
    namespace = kubernetes_namespace.wordpress.metadata[0].name

    annotations = {

      "kubernetes.io/ingress.class"                 = "gce"
      "kubernetes.io/ingress.global-static-ip-name" = "wordpress-ip"
      "networking.gke.io/managed-certificates"      = "wordpress-cert"
      "networking.gke.io/v1beta1.FrontendConfig"    = "wordpress-frontend"

    }

  }

  spec {

    rule {

      host = var.domain

      http {

        path {

          path      = "/"
          path_type = "Prefix"

          backend {

            service {

              name = kubernetes_service.wordpress.metadata[0].name

              port {

                number = 80

              }

            }

          }

        }

      }

    }

  }

}
