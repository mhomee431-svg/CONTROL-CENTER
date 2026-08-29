# ── Foundation outputs — wire these into CI/CD, runbook, and tfvars ──────────

output "ci_deploy_role_arn" {
  description = "OIDC role ARN for GitHub Actions deploy. Set this as the AWS_DEPLOY_ROLE_ARN secret in backend-deploy.yml."
  value       = aws_iam_role.ci_deploy.arn
}

output "ci_verify_role_arn" {
  description = "OIDC read-only role ARN for the IAM foundation verification workflow (aws-iam-foundation.yml). Read-only: identity, simulate-principal-policy, assume-smoke."
  value       = aws_iam_role.ci_verify.arn
}

output "operator_role_arn" {
  description = "Role to assume for all Terraform operation (never run as root / never use admin keys)."
  value       = aws_iam_role.operator.arn
}

output "bootstrap_user_arn" {
  description = "Bootstrap user (only assumes the operator role)."
  value       = aws_iam_user.bootstrap.arn
}

output "bootstrap_access_key_id" {
  description = "Bootstrap access key id. **Store the secret once**; it is produced by `terraform output -json` only at apply."
  value       = aws_iam_access_key.bootstrap.id
  sensitive   = true
}

output "bootstrap_secret_key" {
  description = "Bootstrap secret key (RETURNED ONLY AT CREATION — download it during the first apply)."
  value       = aws_iam_access_key.bootstrap.secret
  sensitive   = true
}

output "bootstrap_profile" {
  description = "Local AWS config profile snippet to use the bootstrap key with role assumption."
  value       = <<-EOT
    [profile hyperlocal-ops]
    region = ${var.aws_region}
    # use export AWS_PROFILE=hyperlocal-ops below
    role_arn = ${aws_iam_role.operator.arn}
    source_profile = hyperlocal-bootstrap
  EOT
}

output "monitor_role_arn" {
  value = aws_iam_role.monitor.arn
}
output "db_operator_role_arn" {
  value = aws_iam_role.db_operator.arn
}
output "s3_backup_role_arn" {
  value = aws_iam_role.s3_backup.arn
}

output "state_bucket" {
  value = aws_s3_bucket.tf_state.id
}
output "lock_table" {
  value = aws_dynamodb_table.tf_lock.id
}
output "github_oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}