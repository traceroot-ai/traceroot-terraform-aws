# deploy/terraform/aws/versions.tf
terraform {
  # 1.3, not 1.0: object type constraints use optional(), which is 1.3, and the
  # SQL-gateway guard uses a lifecycle precondition, which is 1.2. The old floor
  # was already below what this module used, so a 1.0 or 1.1 consumer failed at
  # parse time with an error that named neither.
  required_version = ">= 1.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.79.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}
