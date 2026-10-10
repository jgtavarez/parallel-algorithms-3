terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 8.0"
    }
  }

  # The bucket is passed on init: terraform init -backend-config="bucket=<project>-tfstate"
  backend "gcs" {
    prefix = "terraform/state"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# API Gateway resources are only available in the beta provider.
provider "google-beta" {
  project = var.project_id
  region  = var.region
}
