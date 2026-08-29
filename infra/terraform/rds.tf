# ── RDS PostgreSQL — FREE-TIER shape (private, db.t3.micro, 20GB gp2) ────────
# 750 hours/month of db.t3.micro + 20GB storage are both in the 12-month free
# tier => $0. Backups disabled (snapshot storage would outlive the allowance).

resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-db-subnets"
  subnet_ids = [aws_subnet.app.id, aws_subnet.data.id] # must span 2 AZs
  tags       = { Name = "${local.name_prefix}-db-subnets" }
}

# Generated once; lives only in Terraform state + the SSM SecureString below.
resource "random_password" "master" {
  length           = 32
  special          = true
  override_special = "_!$%^"
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
}

resource "aws_db_instance" "this" {
  identifier             = "${local.name_prefix}-db"
  engine                 = "postgres"
  engine_version         = "16.15" # pinned to an available minor in ap-south-1 (16.3 was retired)
  instance_class         = var.db_instance_class    # db.t3.micro (free tier)
  allocated_storage      = var.db_allocated_storage # 20GB (free tier)
  storage_type           = "gp2"                    # free-tier eligible
  storage_encrypted      = true
  db_name                = var.db_name
  username               = var.db_username
  password               = random_password.master.result
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  # Phase 3 guarantee retained: the database is NEVER publicly exposed.
  publicly_accessible        = false
  multi_az                   = false
  backup_retention_period    = 0
  skip_final_snapshot        = true
  delete_automated_backups   = true
  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true

  tags = { Name = "${local.name_prefix}-db" }
}

# Connection string via SSM SecureString (FREE) — deliberately NOT Secrets
# Manager ($0.40/secret/month and no free tier). The instance role may read
# /<project>/<environment>/* only.
resource "aws_ssm_parameter" "database_url" {
  name        = "/${var.project_name}/${var.environment}/database_url"
  description = "DATABASE_URL for the app instance (points at the private RDS)."
  type        = "SecureString"
  value       = "postgresql+asyncpg://${var.db_username}:${urlencode(random_password.master.result)}@${aws_db_instance.this.endpoint}/${var.db_name}"

  tags = { Name = "${local.name_prefix}-db-url" }
}
