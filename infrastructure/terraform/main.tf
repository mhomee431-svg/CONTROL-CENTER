# ── Hyperlocal — FREE-TIER networking (public EC2 + private RDS) ────────────
# 100% AWS 12-month Free-Tier topology (paid-tier refactor of the old ECS/NAT/
# ALB design — that code remains available in git history for the upgrade):
#   * NO NAT Gateways — the app EC2 sits in a PUBLIC subnet with an IGW route
#     (free internet egress for apt / docker pulls / provider APIs).
#   * NO ALB — a stable Elastic IP + Caddy (reverse proxy, auto-TLS) on the box.
#   * NO ElastiCache — Redis runs as a local Docker container on the EC2.
#   * RDS db.t3.micro (750h/mo free) in a data subnet with NO default route —
#     reachable only from the app SG on 5432, never from the internet.
#   * S3 Gateway endpoint (free) keeps backend → S3 traffic inside the VPC.

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  vpc_id      = aws_vpc.this.id
  az_a        = "${var.aws_region}a"
  az_b        = "${var.aws_region}b"
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name_prefix}-vpc" }
}

# Public subnet (AZ a) — hosts ONLY the single app EC2 (Caddy reverse proxy).
resource "aws_subnet" "app" {
  vpc_id                  = local.vpc_id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = local.az_a
  map_public_ip_on_launch = true
  tags                    = { Name = "${local.name_prefix}-public-${local.az_a}" }
}

# Data subnet (AZ b) — RDS only. Different AZ than the app subnet so the
# db subnet group spans 2 AZs (AWS requirement), still no public IP mapping.
resource "aws_subnet" "data" {
  vpc_id                  = local.vpc_id
  cidr_block              = var.data_subnet_cidr
  availability_zone       = local.az_b
  map_public_ip_on_launch = false
  tags                    = { Name = "${local.name_prefix}-data-${local.az_b}" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = local.vpc_id
  tags   = { Name = "${local.name_prefix}-igw" }
}

# ── Route tables ─────────────────────────────────────────────────────────────
# Public: app subnet → IGW (free egress; no NAT anywhere).
resource "aws_route_table" "public" {
  vpc_id = local.vpc_id
  tags   = { Name = "${local.name_prefix}-public-rt" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "app" {
  subnet_id      = aws_subnet.app.id
  route_table_id = aws_route_table.public.id
}

# Data: isolated — only the implicit local (VPC) route plus the S3 gateway
# endpoint route (added in vpc_endpoints.tf). RDS cannot reach the internet.
resource "aws_route_table" "data" {
  vpc_id = local.vpc_id
  tags   = { Name = "${local.name_prefix}-data-rt" }
}

resource "aws_route_table_association" "data" {
  subnet_id      = aws_subnet.data.id
  route_table_id = aws_route_table.data.id
}
