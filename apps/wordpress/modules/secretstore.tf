resource "kubernetes_manifest" "secretstore" {

  manifest = {

    apiVersion = "external-secrets.io/v1"

    kind = "SecretStore"

    metadata = {

      name = "gcp-secretmanager"

      namespace = kubernetes_namespace.wordpress.metadata[0].name

    }

    spec = {

      provider = {

        gcpsm = {

          projectID = "gke-prod-demo-001"

        }

      }

    }

  }

}
