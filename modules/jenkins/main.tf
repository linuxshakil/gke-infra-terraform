resource "kubernetes_namespace" "cicd" {
  metadata {
    name = "cicd"
  }
}

resource "google_service_account" "jenkins_sa" {
  account_id   = "jenkins-gke-sa"
  display_name = "Jenkins Service Account for GKE"
  project      = var.project_id
}

# Jenkins ko Artifact Registry push karne ki permission
resource "google_project_iam_member" "jenkins_artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.jenkins_sa.email}"
}

# Workload Identity binding — Jenkins pod is SA ko "impersonate" karega
resource "google_service_account_iam_member" "jenkins_workload_identity" {
  service_account_id = google_service_account.jenkins_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[cicd/jenkins]"
}

resource "helm_release" "jenkins" {
  name       = "jenkins"
  repository = "https://charts.jenkins.io"
  chart      = "jenkins"
  namespace  = kubernetes_namespace.cicd.metadata[0].name
  version    = "5.7.15"

  values = [
    yamlencode({
      controller = {
        serviceType = "LoadBalancer"
        resources = {
          requests = { cpu = "500m", memory = "1Gi" }
          limits   = { cpu = "1", memory = "2Gi" }
        }
        installPlugins = [
          "kubernetes:4266.v03deeddbf6a1",
          "workflow-aggregator:600.vb_57cdd26fdd7",
          "git:5.2.2",
          "configuration-as-code:1810.v9b_c30a_249a_4c",
          "docker-workflow:580.vc0c340686b_54"
        ]
      }
      serviceAccount = {
        create = false
        name   = "jenkins"
        annotations = {
          "iam.gke.io/gcp-service-account" = google_service_account.jenkins_sa.email
        }
      }
      persistence = {
        enabled = true
        size    = "8Gi"
      }
    })
  ]
}

resource "kubernetes_service_account" "jenkins" {
  metadata {
    name      = "jenkins"
    namespace = kubernetes_namespace.cicd.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.jenkins_sa.email
    }
  }
}
