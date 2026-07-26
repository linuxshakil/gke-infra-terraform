#########################################################
# Artifact Registry Repository
#########################################################

resource "google_artifact_registry_repository" "backup" {

  project = var.project_id

  location = var.region

  repository_id = "backup-images"

  description = "Docker images for backup jobs"

  format = "DOCKER"

}
