output "repository_name" {

  value = google_artifact_registry_repository.backup.repository_id

}

output "repository_url" {

  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.backup.repository_id}"

}
