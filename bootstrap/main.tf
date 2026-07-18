terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
  # Jaanbujh kar yahan koi backend block nahi hai —
  # ye state LOCAL rahega (bootstrap/terraform.tfstate)
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_storage_bucket" "tf_state" {
  name          = var.bucket_name
  location      = var.region
  project       = var.project_id
  force_destroy = false # production mein accidental delete se bachane ke liye

  versioning {
    enabled = true
  }

  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      num_newer_versions = 5 # sirf last 5 versions rakho, purane auto-delete
    }
    action {
      type = "Delete"
    }
  }
}
