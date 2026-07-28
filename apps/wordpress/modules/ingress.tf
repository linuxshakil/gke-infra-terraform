resource "kubernetes_ingress_v1" "wordpress" {

  metadata {

    name = "wordpress"

    namespace = kubernetes_namespace.wordpress.metadata[0].name

    annotations = {

      "kubernetes.io/ingress.class" = "gce"

      "kubernetes.io/ingress.global-static-ip-name" = google_compute_global_address.wordpress_ip.name

      "networking.gke.io/managed-certificates" = kubernetes_manifest.managed_certificate.manifest.metadata.name

      "networking.gke.io/v1beta1.FrontendConfig" = "wordpress-frontend"

    }

  }

  spec {

    rule {

      host = var.domain

      http {

        path {

          path = "/"

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

  depends_on = [

    kubernetes_manifest.managed_certificate,

    google_compute_global_address.wordpress_ip,

    kubernetes_service.wordpress

  ]

}
