resource "kubernetes_namespace" "wordpress" {

  metadata {

    name = "wordpress"

  }

}
