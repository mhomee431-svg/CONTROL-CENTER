# ── Security groups — only required traffic (free-tier edition) ─────────────
# app : 80/443 in from the world (Caddy reverse proxy / ACME challenge).
#       No SSH port — shell access is Session Manager (IAM role based, free).
# rds : 5432 in from the app SG ONLY. No egress block (SGs are stateful; a
#       database never originates connections).

resource "aws_security_group" "app" {
  name_prefix = "${local.name_prefix}-app-"
  description = "App EC2: 80+443 via Caddy; shell via Session Manager only."
  vpc_id      = local.vpc_id

  ingress {
    description = "HTTP (Caddy reverse proxy + ACME HTTP-01 challenge)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS (Caddy auto-TLS once domain_name is set)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = var.admin_cidr == "" ? [] : [1]
    content {
      description = "Optional admin CIDR (e.g. your IP, for later tooling)"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [var.admin_cidr]
    }
  }

  egress {
    description = "All outbound (apt, docker pulls, RDS 5432, S3 via endpoint)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-app-sg" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "rds" {
  name_prefix = "${local.name_prefix}-rds-"
  description = "Postgres 5432 from the app SG only. Never public."
  vpc_id      = local.vpc_id

  ingress {
    description     = "postgres from the app SG only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }
  # Deliberately NO egress block: RDS never originates connections.

  tags = { Name = "${local.name_prefix}-rds-sg" }

  lifecycle {
    create_before_destroy = true
  }
}
