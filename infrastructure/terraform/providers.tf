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
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # ── REMOTE STATE ───────────────────────────────────────────────────────────
  # Enabled (Phase 3 prep). Bucket + lock table were created by the Phase 2
  # foundation apply (names derived from foundation locals:
  #   hyperlocal-<account_id>-tfstate / terraform-locks).
  # Terraform backends cannot interpolate variables — values are pinned.
  # NOTE: keep one state key PER ENVIRONMENT (change "staging" below when
  # running the production tfvars) so environments never share state.
  backend "s3" {
    bucket         = "hyperlocal-935173128886-tfstate"
    key            = "hyperlocal/production/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

provider "random" {}