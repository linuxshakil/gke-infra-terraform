#########################################################
# GKE Node Service Account
#########################################################

resource "google_service_account" "node_sa" {

  account_id   = "prod-gke-cluster-node-sa"
  display_name = "GKE Node Pool Service Account"

}

#########################################################
# Node Permissions
#########################################################

resource "google_project_iam_member" "node_logging" {

  project = var.project_id

  role = "roles/logging.logWriter"

  member = "serviceAccount:${google_service_account.node_sa.email}"

}

resource "google_project_iam_member" "node_monitoring" {

  project = var.project_id

  role = "roles/monitoring.metricWriter"

  member = "serviceAccount:${google_service_account.node_sa.email}"

}

resource "google_project_iam_member" "node_artifact_reader" {

  project = var.project_id

  role = "roles/artifactregistry.reader"

  member = "serviceAccount:${google_service_account.node_sa.email}"

}

resource "google_project_iam_member" "node_stackdriver" {

  project = var.project_id

  role = "roles/stackdriver.resourceMetadata.writer"

  member = "serviceAccount:${google_service_account.node_sa.email}"

}
