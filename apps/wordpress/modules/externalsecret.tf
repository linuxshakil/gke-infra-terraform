resource "kubernetes_manifest" "externalsecret" {

  manifest = {

    apiVersion = "external-secrets.io/v1"

    kind = "ExternalSecret"

    metadata = {

      name = "wordpress-db"

      namespace = kubernetes_namespace.wordpress.metadata[0].name

    }

    spec = {

      refreshInterval = "1h"

      secretStoreRef = {

        name = kubernetes_manifest.secretstore.manifest.metadata.name

        kind = "SecretStore"

      }

      target = {

        name = "wordpress-db"

      }

      data = [

        {

          secretKey = "password"

          remoteRef = {

            key = "wordpress-db-password"

          }

        }

      ]

    }

  }

  depends_on = [

    kubernetes_manifest.secretstore

  ]

}
