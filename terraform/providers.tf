terraform {
  required_version = ">= 1.9.0"

  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.83"
    }
  }
}

# Credentials are never set here. The provider reads them from the environment:
# SCW_ACCESS_KEY, SCW_SECRET_KEY, SCW_DEFAULT_PROJECT_ID, SCW_DEFAULT_ORGANIZATION_ID.
# Source them from the gitignored .env before running Terraform:
#
#   set -a && source .env && set +a
#
provider "scaleway" {
  zone   = var.zone
  region = var.region
}
