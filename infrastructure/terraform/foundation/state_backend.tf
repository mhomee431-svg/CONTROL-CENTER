# ── Terraform remote state backend ───────────────────────────────────────────
# Created on the FIRST apply (local state). Enable the s3 "backend" block in
# main.tf afterwards so subsequent runs are centrally stored and locked.

resource "aws_s3_bucket" "tf_state" {
  bucket        = local.state_bucket
  force_destroy = true # state is recoverable from versions; still, keep private
  tags = {
    Name    = local.state_bucket
    Purpose = "Terraform remote state encrypted"
  }
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "aws:kms" }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tf_lock" {
  name         = var.lock_table
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name    = var.lock_table
    Purpose = "Terraform state locking"
  }
}

# Bucket policy: only this account may read/write its own state.
data "aws_iam_policy_document" "state_bucket_policy" {
  statement {
    sid     = "SelfAccountStateOnly"
    effect  = "Allow"
    actions = ["s3:*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.acct}:root"]
    }
    resources = [
      aws_s3_bucket.tf_state.arn,
      "${aws_s3_bucket.tf_state.arn}/*",
    ]
  }
}

resource "aws_s3_bucket_policy" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  policy = data.aws_iam_policy_document.state_bucket_policy.json
}