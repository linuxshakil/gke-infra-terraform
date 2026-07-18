resource "kubernetes_storage_class" "wordpress" {

  metadata {
    name = "wordpress-storage"
  }

  storage_provisioner = "pd.csi.storage.gke.io"

  parameters = {
    type = "pd-balanced"
  }

  reclaim_policy      = "Retain"
  volume_binding_mode = "WaitForFirstConsumer"

  allow_volume_expansion = true
}

resource "kubernetes_persistent_volume_claim" "wordpress" {

  metadata {
    name      = "wordpress-data"
    namespace = kubernetes_namespace.wordpress.metadata[0].name
  }

  spec {

    access_modes = [
      "ReadWriteOnce"
    ]

    storage_class_name = kubernetes_storage_class.wordpress.metadata[0].name

    resources {

      requests = {
        storage = "20Gi"
      }

    }
  }

  depends_on = [
    kubernetes_namespace.wordpress,
    kubernetes_storage_class.wordpress
  ]
}
