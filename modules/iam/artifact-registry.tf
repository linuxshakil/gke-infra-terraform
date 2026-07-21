#########################################################
# Artifact Registry Access
#########################################################

#
# GitHub Actions
# Push Docker Images
#
resource "google_project_iam_member" "github_artifact_registry_writer" {

  project = var.project_id

  role = "roles/artifactregistry.writer"

  member = "serviceAccount:${google_service_account.github_actions.email}"

}

#
# GKE Nodes
# Pull Docker Images
#
resource "google_project_iam_member" "node_artifact_registry_reader" {

  project = var.project_id

  role = "roles/artifactregistry.reader"

  member = "serviceAccount:${data.google_service_account.node_sa.email}"

}
