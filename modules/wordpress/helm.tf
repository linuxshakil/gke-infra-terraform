resource "helm_release" "wordpress" {

  name             = "wordpress"
  namespace        = kubernetes_namespace.wordpress.metadata[0].name

  repository       = "https://charts.bitnami.com/bitnami"
  chart            = "wordpress"

  create_namespace = false
  cleanup_on_fail  = true
  wait             = true
  timeout          = 900

  values = [
    templatefile("${path.module}/values.yaml.tpl", {
      domain  = var.domain
      db_host = var.db_host
      db_name = var.db_name
      db_user = var.db_user
    })
  ]

  depends_on = [
    kubernetes_namespace.wordpress,
    kubernetes_secret.wordpress_db,
    kubernetes_storage_class.wordpress,
    kubernetes_persistent_volume_claim.wordpress,
    kubernetes_service_account.wordpress
  ]
}
