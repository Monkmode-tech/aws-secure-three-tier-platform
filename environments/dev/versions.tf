terraform {
  # >= 1.10 for S3-native state locking (use_lockfile), no DynamoDB table needed.
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Partial configuration; values come from backend.hcl (see backend.hcl.example).
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "github.com/Monkmode-tech/aws-secure-three-tier-platform"
      Owner       = var.owner
    }
  }
}
