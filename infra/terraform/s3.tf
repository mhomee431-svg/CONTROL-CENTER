# ── S3 uploads bucket — PRIVATE, free-tier sized ────────────────────────────
# Backend uploads go here over the free S3 Gateway endpoint. All four public
# access blocks + TLS-only bucket policy => the bucket can never be public.

locals {
  uploads_bucket = var.uploads_bucket_name != "" ? var.uploads_bucket_name : "${var.project_name}-${data.aws_caller_identity.current.account_id}-uploads"
}

resource "aws_s3_bucket" "uploads" {
  bucket        = local.uploads_bucket
  force_destroy = true # easy teardown; flip to false before going live
  tags          = { Name = local.uploads_bucket }
}

resource "aws_s3_bucket_versioning" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  versioning_configuration {
    status = "Disabled" # version copies double storage; stay inside 5GB free
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # free; SSE-KMS would burn request $ beyond free tier
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

# Even a misconfigured ACL/policy can never serve objects over HTTP.
resource "aws_s3_bucket_policy" "uploads_tls_only" {
  bucket = aws_s3_bucket.uploads.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.uploads.arn, "${aws_s3_bucket.uploads.arn}/*"]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })
}
