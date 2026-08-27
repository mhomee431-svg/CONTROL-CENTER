# ── Outputs — wire these into CI/CD, Flutter builds, and the runbook ─────────

output "alb_dns_name" {
  description = "Public ALB DNS name (point api.<domain> here if not using Route53)."
  value       = aws_lb.main.dns_name
}

output "api_url" {
  description = "Production API HTTPS URL."
  value       = "https://${var.api_subdomain}.${var.domain_name}"
}

output "ecr_repository_url" {
  description = "ECR repo URL to push the backend image in CI/CD."
  value       = aws_ecr_repository.backend.repository_url
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "web_service_name" {
  value = aws_ecs_service.web.name
}

output "web_task_family" {
  value = aws_ecs_task_definition.web.family
}

output "database_secret_arn" {
  description = "Secrets Manager ID holding DATABASE_URL (ECS-native injection)."
  value       = aws_secretsmanager_secret.database.arn
}

output "app_secret_arn" {
  description = "Secrets Manager ID for the runtime JSON secret bundle (provider keys)."
  value       = aws_secretsmanager_secret.backend.arn
}

output "s3_bucket_name" {
  value = aws_s3_bucket.uploads.id
}

output "redis_endpoint" {
  value = local.redis_endpoint
}

output "acm_certificate_arn" {
  value = var.create_acm_certificate ? aws_acm_certificate.next[0].arn : var.acm_certificate_arn
}