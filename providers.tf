terraform {

  required_version = ">= 1.9"

  required_providers {

    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }

    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
provider "google-beta" {
  project = var.project_id
  region  = var.region
}

data "google_client_config" "default" {}

provider "kubernetes" {

  host = "https://${module.gke.cluster_endpoint}"

  cluster_ca_certificate = base64decode(module.gke.cluster_ca_cert)

  token = data.google_client_config.default.access_token
}

provider "helm" {

  kubernetes {

    host = "https://${module.gke.cluster_endpoint}"

    cluster_ca_certificate = base64decode(module.gke.cluster_ca_cert)

    token = data.google_client_config.default.access_token
  }
}
