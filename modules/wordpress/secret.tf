resource "kubernetes_secret" "wordpress_db" {

  metadata {
    name      = "wordpress-db"
    namespace = kubernetes_namespace.wordpress.metadata[0].name
  }

  type = "Opaque"

  data = {
    password = var.db_password
  }
}
