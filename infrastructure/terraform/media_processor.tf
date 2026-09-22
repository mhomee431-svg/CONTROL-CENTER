# ── Phase 3: Media-processor Lambda ──────────────────────────────────────────
# The Lambda runs in the VPC (two private data subnets, AZ a + AZ b) so it can
# reach the private RDS on 5432. It is triggered by S3 Object Created events
# via EventBridge and advances each Media row through its lifecycle.
#
# VPC PLACEMENT:
#   AWS requires Lambda VPC functions to span at least 2 subnets in different
#   AZs. Both subnets share the isolated `data` route table (no internet route;
#   S3 access via the free S3 Gateway endpoint in vpc_endpoints.tf).
#
# PACKAGING (single source of truth for the Lambda's Python deps):
#   The Lambda zip is built from infrastructure/lambda_staging/ (populated by
#   infrastructure/build_lambda_staging.py). The staging dir contains ONLY
#   lambda_function.py + the app/ package — NO .env, __pycache__, tests,
#   alembic, scripts, or other secrets/clutter.
#
#   PYTHON DEPS (boto3, sqlalchemy, pydantic, asyncpg, ...):
#     Option A — bundle in the zip (simplest for free-tier / small deps):
#       1. Run the build script:  python infrastructure/build_lambda_staging.py
#       2. Install deps for the Lambda runtime (linux x86_64):
#          pip install --platform manylinux2014_x86_64 --only-binary=:all: \
#            -r backend/requirements.txt -t infrastructure/lambda_staging/
#     Option B — Lambda Layer (cleaner for large deps / reuse across functions):
#       Build a layer zip from the same requirements.txt and attach it via
#       `layers = [aws_lambda_layer_version.xxx.arn]` on the function below.
#
#   The build script (infrastructure/build_lambda_staging.py) is the canonical
#   packaging step. Run it BEFORE `terraform plan/apply` so the archive source
#   dir exists. The `data "archive_file"` below will fail if the dir is missing.
#
#   Verified test suite (test_lambda_s3_event_phase3.py) runs the same
#   lambda_function.py with injected SQLite + fake provider — no AWS/Postgres
#   needed. The Terraform here wires the REAL boto3 + RDS path.
#
# SECRETS:
#   DATABASE_URL comes from the SSM SecureString (aws_ssm_parameter.database_url)
#   created in rds.tf. The Lambda's environment variable is set from the
#   decrypted value at apply time. No secrets in git, no .env in the zip.

# ── Second private data subnet (AZ a) for Lambda VPC placement ──────────────
# Shares the isolated `data` route table (no internet route; S3 via Gateway
# endpoint). The existing data subnet is in AZ b; this one is in AZ a so the
# Lambda's 2-subnet VPC requirement is satisfied across 2 AZs.
resource "aws_subnet" "data_a" {
  vpc_id                  = local.vpc_id
  cidr_block              = var.data_subnet_cidr_a
  availability_zone       = local.az_a
  map_public_ip_on_launch = false
  tags                    = { Name = "${local.name_prefix}-data-${local.az_a}" }
}

resource "aws_route_table_association" "data_a" {
  subnet_id      = aws_subnet.data_a.id
  route_table_id = aws_route_table.data.id
}

# ── Lambda security group ────────────────────────────────────────────────────
# Egress: RDS 5432 (to the RDS SG) + S3 HTTPS (443 to 0.0.0.0/0, but the data
# route table has no internet route so this reaches ONLY the S3 Gateway
# endpoint — no NAT, no internet exposure).
resource "aws_security_group" "lambda_media" {
  name_prefix = "${local.name_prefix}-lambda-media-"
  description = "Lambda media processor: egress to RDS 5432 + S3 (via Gateway endpoint)"
  vpc_id      = local.vpc_id

  egress {
    description     = "RDS postgres"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.rds.id]
  }

  egress {
    description = "S3 via Gateway endpoint (HTTPS). Data subnet has no internet route,"
                 " so 0.0.0.0/0 on 443 reaches only S3."
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-lambda-media-sg" }

  lifecycle {
    create_before_destroy = true
  }
}

# Allow the Lambda SG to reach RDS on 5432 (in addition to the app SG).
resource "aws_security_group_rule" "lambda_to_rds" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = aws_security_group.lambda_media.id
  description              = "Lambda media processor → RDS postgres"
}

# ── Lambda IAM role ──────────────────────────────────────────────────────────
data "aws_iam_policy_document" "lambda_media_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_media" {
  name               = "${local.name_prefix}-lambda-media-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_media_assume.json
  tags               = { Name = "${local.name_prefix}-lambda-media-role" }
}

# CloudWatch Logs: create log group/stream, put events. Required for any Lambda.
resource "aws_iam_role_policy" "lambda_media_logs" {
  name = "${local.name_prefix}-lambda-media-logs"
  role = aws_iam_role.lambda_media.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "arn:aws:logs:*:*:*"
    }]
  })
}

# S3: read/write/list/delete on the uploads bucket (media processing).
resource "aws_iam_role_policy" "lambda_media_s3" {
  name = "${local.name_prefix}-lambda-media-s3"
  role = aws_iam_role.lambda_media.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket",
        "s3:DeleteObject"
      ]
      Resource = [
        aws_s3_bucket.uploads.arn,
        "${aws_s3_bucket.uploads.arn}/*"
      ]
    }]
  })
}

# ── Lambda source zip (archive_file) ────────────────────────────────────────
# Packages infrastructure/lambda_staging/ (built by build_lambda_staging.py).
# The zip is recreated whenever the staging dir changes (source_code_hash tracks
# the content). Run the build script BEFORE terraform plan/apply.
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda_staging"
  output_path = "${path.module}/lambda.zip"
}

# ── Lambda function ──────────────────────────────────────────────────────────
resource "aws_lambda_function" "media_processor" {
  function_name = "${local.name_prefix}-media-processor"
  role          = aws_iam_role.lambda_media.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  memory_size   = var.media_lambda_memory_mb
  timeout       = var.media_lambda_timeout_sec

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  vpc_config {
    subnet_ids         = [aws_subnet.data.id, aws_subnet.data_a.id]
    security_group_ids = [aws_security_group.lambda_media.id]
  }
  environment {
    variables = {
      DATABASE_URL     = aws_ssm_parameter.database_url.value
      STORAGE_PROVIDER = "s3"
      S3_BUCKET_NAME   = aws_s3_bucket.uploads.bucket
      S3_REGION        = var.aws_region
    }
  }

  tags = { Name = "${local.name_prefix}-media-processor" }
}

# ── EventBridge rule: S3 Object Created → Lambda ────────────────────────────
# Matches S3 object-created events for the uploads bucket and routes them to
# the media-processor Lambda. S3 publishes to EventBridge when the bucket is
# configured with an eventbridge notification (below).
resource "aws_cloudwatch_event_rule" "s3_object_created" {
  name          = "${local.name_prefix}-s3-object-created"
  description   = "Trigger media-processor Lambda on S3 object-created events"
  event_pattern = jsonencode({
    source      = ["aws.s3"]
    "detail-type" = ["Object Created"]
    detail = {
      bucket = {
        name = [aws_s3_bucket.uploads.bucket]
      }
    }
  })

  tags = { Name = "${local.name_prefix}-s3-object-created" }
}

resource "aws_cloudwatch_event_target" "lambda_media" {
  rule      = aws_cloudwatch_event_rule.s3_object_created.name
  target_id = "media-processor-lambda"
  arn       = aws_lambda_function.media_processor.arn
}

# Allow EventBridge to invoke the Lambda.
resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeS3ObjectCreated"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.media_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.s3_object_created.arn
}

# ── S3 → EventBridge notification ───────────────────────────────────────────
# Enables the uploads bucket to publish object-created events to EventBridge.
# Without this, S3 will not emit events to EventBridge for this bucket.
resource "aws_s3_bucket_notification" "media_events" {
  bucket = aws_s3_bucket.uploads.id

  eventbridge {}
}


