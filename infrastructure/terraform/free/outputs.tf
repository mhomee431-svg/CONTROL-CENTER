# infrastructure/terraform/free/outputs.tf

output "public_ip" {
  description = "App public IPv4. Open http://<ip>/ready once healthy."
  value       = try(aws_instance.app.public_ip, null)
}

output "app_url_health" {
  value       = try("http://${aws_instance.app.public_ip}/health", null)
  description = "Liveness probe URL."
}

output "app_url_ready" {
  value       = try("http://${aws_instance.app.public_ip}/ready", null)
  description = "Readiness probe URL (db + postgis + redis)."
}

output "github_token_parameter" {
  value       = aws_ssm_parameter.github_token.name
  description = "SSM SecureString name to set your GitHub PAT (only if repo private)."
}

output "session_manager_tip" {
  value       = "AWS Console -> EC2 -> select '${var.project}-free-app' -> Connect -> Session Manager. No key pair needed."
  description = "How to get a shell without opening any SSH port."
}

output "instance_identity_doc_role" {
  value       = aws_iam_instance_profile.this.name
  description = "Attached instance profile (SSM core + param read)."
}
