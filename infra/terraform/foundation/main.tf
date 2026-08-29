# ─────────────────────────────────────────────────────────────────────────────
# Hyperlocal — PHASE 2: AWS Account & IAM Foundation  (Stage-0 Terraform)
# ─────────────────────────────────────────────────────────────────────────────
# This applies ONCE, *before* infra/terraform (the application stack). It owns
# only account-level bootstrap concerns:
#   • Terraform state backend (S3) + lock (DynamoDB)
#   • GitHub Actions OIDC provider + a scoped CI/CD deploy role
#   • An "operator" IAM role + a bootstrap IAM user (can ONLY assume that role)
#   • Monitoring / database / S3 backup roles (least privilege, scoped)
#   • Account password policy (no root use at runtime; humans assume roles)
#
# Nothing here creates application resources (VPC/ECS/RDS/…). See the sibling
# `../` module for those. Run order:
#   1. terraform init   (local state — the bucket/table below don't exist yet)
#   2. terraform plan && terraform apply
#   3. move bootstrap upgrade path to the S3 backend created here (see README)

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # ── REMOTE STATE (enabled after first apply created bucket+table) ──
  backend "s3" {
    bucket         = "hyperlocal-935173128886-tfstate" # hyperlocal-<account_id>-tfstate
    key            = "hyperlocal/foundation/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}