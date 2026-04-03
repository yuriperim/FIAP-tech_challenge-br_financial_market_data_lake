terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.38"
    }

    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }

  required_version = ">= 1.2"
}
