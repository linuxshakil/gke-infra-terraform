resource "kubernetes_secret" "wordpress_db" {

  metadata {
    name      = "wordpress-db"
    namespace = kubernetes_namespace.wordpress.metadata[0].name
  }

  type = "Opaque"

  data = {
    mariadb-password = base64encode(var.db_password)
    password         = base64encode(var.db_password)
  }

  depends_on = [
    kubernetes_namespace.wordpress
  ]
}
