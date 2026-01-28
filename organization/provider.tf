terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = "us-east-1"
  profile = "management-sso"  # or "management-admin"

  default_tags {
    tags = {
      Organization = "Noise2Signal LLC"
      ManagedBy    = "terraform"
      Layer        = "organization"
    }
  }
}
