resource "google_project_service" "service_networking" {
  project = var.project_id
  service = "servicenetworking.googleapis.com"

  disable_on_destroy = false
}

#Cloud SQL module use karne se pehle ensure karo ki Terraform se APIs bhi managed hon.
resource "google_project_service" "sqladmin" {
  project = var.project_id
  service = "sqladmin.googleapis.com"

  disable_on_destroy = false
}

resource "google_project_service" "secretmanager" {

  project = var.project_id

  service = "secretmanager.googleapis.com"

  disable_on_destroy = false

}
