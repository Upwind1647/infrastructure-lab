terraform {
  required_version = ">= 1.5.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.52.0"
    }
  }

  # Backend values are passed via tofu init -backend-config in CI.
  backend "s3" {}
}

provider "cloudflare" {
  # Uses CLOUDFLARE_API_TOKEN from the environment.
}
