# ── Single FREE-TIER app EC2: Caddy reverse proxy + local Redis container ───
# t3.micro (750h/mo free) in the PUBLIC subnet behind an Elastic IP (free while
# attached to a running instance). No ALB, no NAT, no SSH port.

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${local.name_prefix}-instance-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
  tags               = { Name = "${local.name_prefix}-instance-role" }
}

# Free shell access without any SSH port + SSM agent parameter fetch.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Least privilege: own SSM params + the uploads bucket ONLY.
resource "aws_iam_role_policy" "instance_app" {
  name = "${local.name_prefix}-instance-app"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadOwnParameters"
        Effect = "Allow"
        Action = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
        Resource = [
          "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/${var.environment}/*"
        ]
      },
      {
        Sid      = "UploadsBucketOnly"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [aws_s3_bucket.uploads.arn, "${aws_s3_bucket.uploads.arn}/*"]
      },
      {
        Sid      = "BackupBucketReadWrite"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [aws_s3_bucket.backups.arn, "${aws_s3_bucket.backups.arn}/*"]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "app" {
  name = "${local.name_prefix}-instance-profile"
  role = aws_iam_role.instance.name
}

# Placeholder SecureString — replace only if the repo is private.
resource "aws_ssm_parameter" "github_token" {
  name        = "/${var.project_name}/${var.environment}/github_token"
  description = "GitHub PAT used at boot to clone private repos. Replace PLACEHOLDER."
  type        = "SecureString"
  value       = "PLACEHOLDER_REPLACE_WITH_GITHUB_PAT"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type # t3.micro (free tier)
  subnet_id              = aws_subnet.app.id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.app.name

  root_block_device {
    volume_type           = "gp2" # free-tier eligible (30GB/mo allowance)
    volume_size           = var.root_volume_gb
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_tokens   = "required" # IMDSv2 only
    http_endpoint = "enabled"
    # hop limit 2: lets the Docker containers on this host use the instance
    # role for private S3 uploads (default 1 would block container access).
    http_put_response_hop_limit = 2
  }

  monitoring = false # detailed CloudWatch metrics would leave the free tier

  user_data_replace_on_change = null

  user_data_base64 = base64encode(
    templatefile(
      "${path.module}/user_data.sh.tpl",
      {
        region       = var.aws_region
        project      = var.project_name
        environment  = var.environment
        branch       = var.github_branch
        repo_url     = var.github_repo
        app_dir      = "/opt/hyperlocal"
        db_url_param = aws_ssm_parameter.database_url.name
        s3_bucket    = aws_s3_bucket.uploads.bucket
        caddy_config = var.domain_name != "" ? "${var.domain_name} {\n    reverse_proxy 127.0.0.1:8000\n}" : ":80 {\n    reverse_proxy 127.0.0.1:8000\n}"
      }
    )
  )

  tags = { Name = "${local.name_prefix}-app" }

  timeouts {
    create = "15m"
  }

  # The boot script needs the DATABASE_URL param and a reachable database, so
  # the instance is only created after RDS is available.
  depends_on = [aws_db_instance.this, aws_ssm_parameter.database_url]

  lifecycle {
    ignore_changes = [ami] # OS updates are a deliberate replacement later
  }
}

# Stable public address; free while attached to a RUNNING instance.
resource "aws_eip" "app" {
  domain   = "vpc"
  instance = aws_instance.app.id
  tags     = { Name = "${local.name_prefix}-eip" }
}
