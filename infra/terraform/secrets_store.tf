# ── KMS ─────────────────────────────────────────────────────────────────────
# Customer-managed key used to encrypt the secret bundle and S3 objects.
resource "aws_kms_key" "this" {
  description             = "${var.project_name} ${var.environment} app KMS key"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  tags                    = { Name = "${local.name_prefix}-kms" }
}

resource "aws_kms_alias" "this" {
  name          = "alias/${local.name_prefix}"
  target_key_id = aws_kms_key.this.id
}

# ── AWS Secrets Manager ─────────────────────────────────────────────────────
# Created empty on purpose. The operator pastes the JSON secret bundle via the
# console/CLI (never in git or tfvars). ECS task references it by name for the
# hydration helper and for direct `secrets:` injection.
resource "aws_secretsmanager_secret" "backend" {
  name                    = "${var.secrets_secret_name}/${var.environment}"
  description             = "Hyperlocal backend runtime secrets (flat JSON key: value)"
  kms_key_id              = aws_kms_key.this.arn
  recovery_window_in_days = 7
  tags                    = { Name = "${local.name_prefix}-secrets" }

  lifecycle {
    ignore_changes = [recovery_window_in_days]
  }
}

# ── S3 (product images) ─────────────────────────────────────────────────────
# Private bucket. The app either returns presigned GETs or we bolt on a
# CloudFront distribution later. Flutter never receives S3 credentials.
resource "aws_s3_bucket" "uploads" {
  bucket        = "${local.name_prefix}-uploads"
  force_destroy = false
  tags          = { Name = "${local.name_prefix}-uploads" }
}

resource "aws_s3_bucket_versioning" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.this.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    id     = "old-versions"
    status = "Enabled"
    noncurrent_version_expiration {
      noncurrent_days = 15
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}