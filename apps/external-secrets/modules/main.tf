resource "google_service_account" "external_secrets" {

  account_id   = "external-secrets-sa"
  display_name = "External Secrets GSA"

}

resource "google_project_iam_member" "secret_accessor" {

  project = var.project_id

  role = "roles/secretmanager.secretAccessor"

  member = "serviceAccount:${google_service_account.external_secrets.email}"

}

resource "kubernetes_service_account" "external_secrets" {

  metadata {

    name      = "external-secrets"
    namespace = "external-secrets"

    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.external_secrets.email
    }

  }

}

resource "google_service_account_iam_member" "workload_identity" {

  service_account_id = google_service_account.external_secrets.name

  role = "roles/iam.workloadIdentityUser"

  member = "serviceAccount:${var.project_id}.svc.id.goog[external-secrets/external-secrets]"

}

resource "helm_release" "external_secrets" {

  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  version          = "0.19.2"

  wait    = true
  timeout = 600

  values = [

    yamlencode({

      serviceAccount = {

        create = false
        name   = kubernetes_service_account.external_secrets.metadata[0].name

      }

    })

  ]

  depends_on = [

    kubernetes_service_account.external_secrets,
    google_project_iam_member.secret_accessor,
    google_service_account_iam_member.workload_identity

  ]

}
