resource "kubernetes_manifest" "wordpress_backendconfig" {

  manifest = {

    apiVersion = "cloud.google.com/v1"

    kind = "BackendConfig"

    metadata = {

      name = "wordpress-backend"

      namespace = kubernetes_namespace.wordpress.metadata[0].name

    }

    spec = {

      timeoutSec = 30

      connectionDraining = {

        drainingTimeoutSec = 60

      }

      healthCheck = {

        checkIntervalSec = 15

        timeoutSec = 5

        healthyThreshold = 2

        unhealthyThreshold = 3

        requestPath = "/"

        port = 80

        type = "HTTP"

      }

    }

  }

}
