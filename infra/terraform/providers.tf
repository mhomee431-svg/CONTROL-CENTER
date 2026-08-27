# Hyperlocal — Terraform providers.
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # ── REMOTE STATE ───────────────────────────────────────────────────────────
  # Uncomment AFTER you create the state bucket (see infra/README.md §Provision
  # order). Terraform backends cannot interpolate variables.
  #
  # backend "s3" {
  #   bucket         = "hyperlocal-terraform-state"   # must exist first
  #   key            = "hyperlocal/production/terraform.tfstate"
  #   region         = "us-east-1"                    # your state lock region
  #   dynamodb_table = "terraform-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}

provider "random" {}