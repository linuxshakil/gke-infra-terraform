terraform {

  required_version = ">= 1.15.0"

  required_providers {

    google = {
      source  = "hashicorp/google"
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

  }

}
