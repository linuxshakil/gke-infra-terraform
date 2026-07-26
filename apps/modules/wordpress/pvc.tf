resource "kubernetes_persistent_volume_claim" "wordpress" {

  metadata {
    name      = "wordpress-data"
    namespace = kubernetes_namespace.wordpress.metadata[0].name
  }

  spec {

    access_modes = [
      "ReadWriteOnce"
    ]

    storage_class_name = "standard-rwo"

    resources {

      requests = {
        storage = "20Gi"
      }

    }

  }

}
