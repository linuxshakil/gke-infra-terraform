terraform {
  required_version = ">= 1.8.0"

  required_providers {

    google = {
      source  = "hashicorp/google"
      version = "~> 6.45"
    }

    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.45"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }

    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.19"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }

    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}
