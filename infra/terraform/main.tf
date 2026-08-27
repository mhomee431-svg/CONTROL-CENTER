# ── Hyperlocal — VPC networking (private-by-default) ────────────────────────
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  azs         = var.availability_zones
  vpc_id      = aws_vpc.this.id
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name_prefix}-vpc" }
}

# ── Subnets ─────────────────────────────────────────────────────────────────
resource "aws_subnet" "public" {
  count                   = length(local.azs)
  vpc_id                  = local.vpc_id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)                           # 10.0.0.0/20, 10.0.16.0/20
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true
  tags = { Name = "${local.name_prefix}-public-${local.azs[count.index]}" }
}

resource "aws_subnet" "private" {
  count             = length(local.azs)
  vpc_id            = local.vpc_id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + 4)                            # 10.0.64.0/20, 10.0.80.0/20
  availability_zone = local.azs[count.index]
  tags = { Name = "${local.name_prefix}-private-${local.azs[count.index]}" }
}

resource "aws_subnet" "data" {                                       # RDS + Redis (private, no NAT dependency)
  count             = length(local.azs)
  vpc_id            = local.vpc_id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + 8)  # 10.0.128.0/20, 10.0.144.0/20
  availability_zone = local.azs[count.index]
  tags = { Name = "${local.name_prefix}-data-${local.azs[count.index]}" }
}

# ── Internet Gateway (public egress + NAT) ──────────────────────────────────
resource "aws_internet_gateway" "this" {
  vpc_id = local.vpc_id
  tags   = { Name = "${local.name_prefix}-igw" }
}

resource "aws_eip" "nat" {
  count  = length(local.azs)
  domain = "vpc"
  tags   = { Name = "${local.name_prefix}-nat-eip-${count.index}" }
}

resource "aws_nat_gateway" "this" {
  count         = length(local.azs)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = { Name = "${local.name_prefix}-nat-${count.index}" }
}

# ── Route tables ────────────────────────────────────────────────────────────
resource "aws_route_table" "public" {
  vpc_id = local.vpc_id
  tags   = { Name = "${local.name_prefix}-public-rt" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count          = length(local.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  count  = length(local.azs)
  vpc_id = local.vpc_id
  tags   = { Name = "${local.name_prefix}-private-rt-${count.index}" }
}

resource "aws_route" "private_nat" {
  count                = length(local.azs)
  route_table_id       = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id       = aws_nat_gateway.this[count.index].id
}

resource "aws_route_table_association" "private" {
  count       = length(local.azs)
  subnet_id   = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_route_table_association" "data" {
  count       = length(local.azs)
  subnet_id   = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}