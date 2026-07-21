resource "helm_release" "external_secrets" {

  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  version          = "0.19.2"

  wait    = true
  timeout = 600

}
