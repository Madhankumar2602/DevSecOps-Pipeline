terraform {
  required_version = ">= 1.10.0" # S3 lock files (use_lockfile)

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

  # Remote state in S3 (bucket created once by bootstrap, see README Step 4).
  # Values come from backend.hcl:  terraform init -backend-config=backend.hcl
  # Locking uses an S3 lock file (use_lockfile), so no DynamoDB table is needed.
  backend "s3" {}
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
