resource "helm_release" "wordpress" {

  name      = "wordpress"
  namespace = kubernetes_namespace.wordpress.metadata[0].name

  repository = "oci://registry-1.docker.io/bitnamicharts"

  chart = "wordpress"

  version = "32.1.12"

  timeout = 900

  wait = true

  values = [
    templatefile("${path.module}/values.yaml.tpl", {
      domain  = var.domain
      db_host = var.db_host
      db_name = var.db_name
      db_user = var.db_user
    })
  ]

  depends_on = [
    kubernetes_secret.wordpress_db,
    kubernetes_service_account.wordpress
  ]
}
