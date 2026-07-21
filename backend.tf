terraform {

  backend "gcs" {

    bucket = "gke-prod-demo-001-tf-state"

    prefix = "gke/prod"
  }

}
