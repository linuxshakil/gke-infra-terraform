#########################################################
# GKE Node Service Account
#########################################################

resource "google_service_account" "node_sa" {

  account_id   = "prod-gke-cluster-node-sa"
  display_name = "GKE Node Pool Service Account"

}

#########################################################
# Node IAM Roles
#########################################################

resource "google_project_iam_member" "node_roles" {

  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/artifactregistry.reader",
    "roles/stackdriver.resourceMetadata.writer"
  ])

  project = var.project_id

  role = each.value

  member = "serviceAccount:${google_service_account.node_sa.email}"

}
