terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
  required_version = ">= 1.5.0"

  # Backend values are passed via `tofu init -backend-config` in CI and local ops.
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "Infrastructure-Lab"
      Environment = "Lab"
      ManagedBy   = "Terraform"
    }
  }
}
