resource "kubernetes_manifest" "wordpress_frontendconfig" {

  manifest = {

    apiVersion = "networking.gke.io/v1beta1"

    kind = "FrontendConfig"

    metadata = {

      name = "wordpress-frontend"

      namespace = kubernetes_namespace.wordpress.metadata[0].name

    }

    spec = {

      redirectToHttps = {

        enabled = true

      }

    }

  }

}
