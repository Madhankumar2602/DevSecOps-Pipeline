terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }

  # Optional: remote state. Create the bucket once (see README step 3), then uncomment.
  # backend "s3" {
  #   bucket       = "shipguard-tfstate-<your-account-id>"
  #   key          = "shipguard/terraform.tfstate"
  #   region       = "ap-south-1"
  #   encrypt      = true
  #   use_lockfile = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Owner     = var.owner
    }
  }
}

data "aws_caller_identity" "current" {}
