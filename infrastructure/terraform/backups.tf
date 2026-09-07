# ── Phase 5 — S3 backup bucket for logical DB backups (DR layer) ─────────────
# backup_db.sh uploads the daily logical dump (+ manifest) here, so a restore
# never depends on a single machine or on RDS-native snapshots alone.
# Retention is enforced by a lifecycle rule: daily backups 30 days, monthly
# backups 365 days. The bucket is PRIVATE (all four public-access blocks).

locals {
  backup_bucket = "${var.project_name}-${data.aws_caller_identity.current.account_id}-backups"
}

resource "aws_s3_bucket" "backups" {
  bucket        = local.backup_bucket
  force_destroy = false # backups must never be force-destroyed
  tags          = { Name = local.backup_bucket }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "backups_tls_only" {
  bucket = aws_s3_bucket.backups.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.backups.arn, "${aws_s3_bucket.backups.arn}/*"]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })
}

# Retention lifecycle: daily → 30 days, monthly → 365 days.
resource "aws_s3_bucket_lifecycle_configuration" "backups_retention" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "daily-retention"
    status = "Enabled"
    filter {
      prefix = "daily/"
    }
    expiration {
      days = 30
    }
  }

  rule {
    id     = "monthly-retention"
    status = "Enabled"
    filter {
      prefix = "monthly/"
    }
    expiration {
      days = 365
    }
  }
}
