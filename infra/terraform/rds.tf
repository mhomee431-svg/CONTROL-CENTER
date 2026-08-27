# ── RDS PostgreSQL (private subnet group, no public access) ─────────────────

resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-rds-subnet"
  subnet_ids = aws_subnet.data[*].id
  tags       = { Name = "${local.name_prefix}-rds-subnet" }
}

resource "aws_db_parameter_group" "main" {
  name        = "${local.name_prefix}-pg"
  family      = "postgres16"
  description = "Hyperlocal Postgres 16 (SSL enforced; PostGIS via extension in migration)"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
}

# Generate the master password once and keep it only in Secrets Manager / state.
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
  engine_version         = "16.3"
  instance_class         = var.database_instance_class
  allocated_storage      = var.database_allocated_storage
  storage_encrypted      = true
  db_name                = var.database_name
  username               = "hyperlocal"
  password               = random_password.master.result
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.main.name
  multi_az               = var.database_multi_az
  backup_retention_period = var.backup_retention_days
  backup_window          = "03:00-03:30"
  maintenance_window     = "sun:05:00-sun:05:30"
  skip_final_snapshot    = false
  final_snapshot_identifier = "${local.name_prefix}-db-final"

  tags = { Name = "${local.name_prefix}-db" }
}

# ── Persist connection string for the app (AWS-native ECS secrets injection) ─
resource "aws_secretsmanager_secret" "database" {
  name        = "${var.secrets_secret_name}/${var.environment}/database"
  description = "RDS connection (DATABASE_URL) for ECS injection"
  kms_key_id  = aws_kms_key.this.arn
  tags        = { Name = "${local.name_prefix}-db-secret" }
}

resource "aws_secretsmanager_secret_version" "database" {
  secret_id     = aws_secretsmanager_secret.database.id
  secret_string = jsonencode({
    DATABASE_URL = "postgresql+asyncpg://hyperlocal:${urlencode(random_password.master.result)}@${aws_db_instance.this.endpoint}/${var.database_name}?sslmode=require"
  })
}