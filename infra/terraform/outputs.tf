# ── Outputs — wire these into CI/CD, the Flutter app, and the runbook ───────

output "app_public_ip" {
  description = "Elastic IP of the app instance (Caddy on 80/443). Point api.<domain> A-record here."
  value       = aws_eip.app.public_ip
}

output "app_instance_id" {
  description = "EC2 instance id (use with Session Manager for shell access)."
  value       = aws_instance.app.id
}

# ── Phase 12: Domain + HTTPS outputs ─────────────────────────────────────
output "api_domain" {
  description = "Production API domain (e.g. api.hyperlocal.in). Empty if not configured."
  value       = var.domain_name
}

output "https_url" {
  description = "HTTPS endpoint for the API (e.g. https://api.hyperlocal.in)."
  value       = var.domain_name != "" ? "https://${var.domain_name}" : "https://${aws_eip.app.public_ip}"
}

output "dns_record" {
  description = "Route53 A-record created for the API domain (if manage_dns=true and domain_name set)."
  value       = var.manage_dns && var.domain_name != "" ? aws_route53_record.api_a_record[0].fqdn : "Not managed — point ${var.domain_name} A-record to ${aws_eip.app.public_ip}"
}

output "caddy_acme_email" {
  description = "Email used for Let's Encrypt ACME account registration."
  value       = var.caddy_acme_email
}

output "cors_origins" {
  description = "CORS origins configured for the production backend (from Terraform variables)."
  value       = local.phase12_cors_origins
}

output "database_endpoint" {
  description = "RDS PostgreSQL endpoint (host:port) — private, app SG only."
  value       = aws_db_instance.this.endpoint
}

output "database_name" {
  value = aws_db_instance.this.db_name
}

output "database_url_ssm_parameter" {
  description = "SSM SecureString holding DATABASE_URL (fetch: aws ssm get-parameter --with-decryption)."
  value       = aws_ssm_parameter.database_url.name
}

output "redis_endpoint" {
  description = "Redis runs as a local Docker container on the app instance (free tier)."
  value       = "127.0.0.1:6379 (on-instance Docker, redis:7-alpine)"
}

output "s3_bucket_name" {
  value = aws_s3_bucket.uploads.id
}

output "backup_bucket_name" {
  description = "S3 bucket holding logical DB backups (Phase 5 DR layer)."
  value       = aws_s3_bucket.backups.id
}

output "github_token_ssm_parameter" {
  description = "SSM SecureString for the bootstrap GitHub PAT (replace the PLACEHOLDER if the repo is private)."
  value       = aws_ssm_parameter.github_token.name
}
