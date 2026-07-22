terraform {
  required_version = ">= 1.15.0"

  required_providers {

    google = {
      source  = "hashicorp/google"
      version = "~> 6.50"
    }

    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.50"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.2"
    }

    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.19"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }

    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.8"
    }
  }
}
