resource "kubernetes_manifest" "managed_certificate" {

  manifest = {

    apiVersion = "networking.gke.io/v1"

    kind = "ManagedCertificate"

    metadata = {

      name = "wordpress-cert"

      namespace = kubernetes_namespace.wordpress.metadata[0].name

    }

    spec = {

      domains = [

        var.domain

      ]

    }

  }

}
