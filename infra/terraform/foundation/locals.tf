# ── Locals shared by the foundation module ───────────────────────────────────
locals {
  prefix = "${var.project_name}-${var.environment}"

  region = var.aws_region
  acct   = var.account_id

  # Bucket names are GLOBAL in S3 — embed the account id so ownership can't
  # collide with another tenant's bucket ("BucketAlreadyExists" guard).
  state_bucket = var.state_bucket != "" ? var.state_bucket : "${var.project_name}-${var.account_id}-tfstate"

  # GitHub OIDC "sub" claims the CI/CD role may accept:
  #   push to default branch  → repo:<org>/<repo>:ref:refs/heads/main
  #   deploy environment      → repo:<org>/<repo>:environment:production
  github_subjects = var.github_allowed_subjects != null ? var.github_allowed_subjects : [
    "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main",
    "repo:${var.github_org}/${var.github_repo}:environment:${var.environment}",
  ]

  # Operators allowed by the role trust: the bootstrap user + any extras.
  operator_principals = concat(
    ["arn:aws:iam::${var.account_id}:user/${var.project_name}-bootstrap"],
    var.operator_principals,
  )
}