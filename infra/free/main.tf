# infra/free/main.tf
# ─────────────────────────────────────────────────────────────────────────────
# AWS FREE-TIER single-instance deployment.
#
# Runs the SAME docker-compose stack used locally (Postgres+Redis+API+Celery)
# on ONE t3.micro, so the product can go live for ~$0 during the free window.
# The production-shaped module (../terraform) stays ready for real traffic.
# See docs/FREE_TIER_CLOUD.md for cost math and the upgrade path.
#
# Deliberately NOT here (each costs money): NAT GW, ALB, RDS, ElastiCache,
# ECS/Fargate, Secrets Manager, interface endpoints. No SSH port either —
# shell access is via Session Manager (free).
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

provider "aws" {
  region = var.region
  # Uses the local default AWS CLI profile — no static keys anywhere.

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Stack     = "free-tier"
    }
  }
}

# ── Latest Ubuntu LTS AMI ────────────────────────────────────────────────────
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

# ── Networking: 1 VPC, 1 public subnet, IGW — all free components ───────────
resource "aws_vpc" "this" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.project}-free-vpc" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.10.1.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project}-free-public-a" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.project}-free-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = { Name = "${var.project}-free-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ── Security group: ONLY required traffic ────────────────────────────────────
resource "aws_security_group" "app" {
  name_prefix = "${var.project}-free-app-"
  description = "Free-tier app: HTTP in via :80 only. SSH only via Session Manager."
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP app traffic (uvicorn published on :80)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = var.admin_cidr == "" ? [] : [1]
    content {
      description = "Optional admin CIDR (e.g. your IP for later tooling)"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [var.admin_cidr]
    }
  }

  egress {
    description = "All outbound (apt, git clone, docker pulls)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-free-app-sg" }

  lifecycle {
    create_before_destroy = true
  }
}

# ── IAM: instance may use Session Manager + read its own parameters ──────────
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
  name               = "${var.project}-free-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

# Free BOTH ways: shell access without SSH AND ssm-agent param fetch.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "read_own_params" {
  name = "${var.project}-free-read-params"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
      Resource = "arn:aws:ssm:${var.region}:*:parameter/${var.project}/free/*"
    }]
  })
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.project}-free-profile"
  role = aws_iam_role.instance.name
}

# Placeholder SecureString replaced by the operator with a real GitHub PAT.
# (Entirely optional while the repository is public.)
resource "aws_ssm_parameter" "github_token" {
  name        = "/${var.project}/free/github_token"
  description = "GitHub PAT used at boot to clone private repos. Replace PLACEHOLDER value."
  type        = "SecureString"
  value       = "PLACEHOLDER_REPLACE_WITH_GITHUB_PAT"

  lifecycle {
    ignore_changes = [value] # manual rotation must survive plans
  }
}

# ── The instance ─────────────────────────────────────────────────────────────
resource "aws_instance" "app" {
  ami                  = data.aws_ami.ubuntu.id
  instance_type        = var.instance_type
  subnet_id            = aws_subnet.public.id
  security_groups      = [aws_security_group.app.id]
  iam_instance_profile = aws_iam_instance_profile.this.name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_gb
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only (free hardening)
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  monitoring = false # detailed CloudWatch metrics would burn credits

  user_data_base64 = base64encode(
    templatefile(
      "${path.module}/user_data.sh.tpl",
      {
        region   = var.region
        project  = var.project
        branch   = var.github_branch
        repo_url = var.github_repo
        app_dir  = "/opt/hyperlocal"
      }
    )
  )

  tags = { Name = "${var.project}-free-app" }

  timeouts {
    create = "15m"
  }

  lifecycle {
    ignore_changes = [ami] # OS updates are a deliberate replacement later
  }
}
