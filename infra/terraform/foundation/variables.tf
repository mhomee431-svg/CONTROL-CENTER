# ── Phase 2 (foundation) input variables ─────────────────────────────────────
# Fill real values in foundation/terraform.tfvars (copy of terraform.tfvars.example).
# Secrets are NEVER placed here.

variable "aws_region" {
  description = "Single deployment region (documented in PHASE2 doc)."
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Resource prefix (lowercase, hyphens allowed)."
  type        = string
  default     = "hyperlocal"
}

variable "environment" {
  description = "Deployment stage mirrored across all roles/tags."
  type        = string
  default     = "production"
}

variable "account_id" {
  description = "12-digit AWS account ID that owns this foundation (required)."
  type        = string
}

variable "tags" {
  description = "Common tags applied to every resource."
  type        = map(string)
  default = {
    Project   = "hyperlocal_customer_app"
    Owner     = "your-email@example.com"
    ManagedBy = "terraform"
  }
}

# ── GitHub Actions (OIDC) ─────────────────────────────────────────────────────
variable "github_org" {
  description = "GitHub organization or username that owns the repository."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (the CI/CD source of truth)."
  type        = string
}

variable "github_allowed_subjects" {
  description = "OIDC 'sub' claims allowed against the CI/CD role. Defaults to the default branch + the production 'environment' for org/repo."
  type        = list(string)
  default     = null
}

# ── App resources the CI/CD + operator roles are scoped to ───────────────────
variable "ecr_repository_name" {
  type    = string
  default = "hyperlocal-backend"
}

variable "ecs_cluster_name" {
  description = "ECS cluster the CI/CD role may update services on."
  type        = string
  default     = "hyperlocal-cluster"
}

variable "secrets_secret_name" {
  description = "Prefix of the Secrets Manager secret name created by the app module."
  type        = string
  default     = "hyperlocal"
}

variable "hosted_zone_id" {
  description = "Route53 hosted zone id (used to scope the operator's DNS grants). Empty = skip DNS grants."
  type        = string
  default     = ""
}

# ── State backend ─────────────────────────────────────────────────────────────
variable "state_bucket" {
  description = "S3 bucket used for remote Terraform state. Empty = '<project_name>-<account_id>-tfstate' (bucket names are global — account id prevents collisions)."
  type        = string
  default     = ""
}

variable "lock_table" {
  description = "DynamoDB table used for Terraform state locking."
  type        = string
  default     = "terraform-locks"
}

# ── Human access (bootstrap) ──────────────────────────────────────────────────
variable "operator_principals" {
  description = "Additional IAM principal ARNs allowed to assume the 'hyperlocal-operator' role (e.g. more admin users). The bootstrap user is always allowed."
  type        = list(string)
  default     = []
}

# ── Phase 25 CI/CD ─────────────────────────────────────────────────────────────
variable "github_environments" {
  description = "GitHub environments the CI/CD role may assume via OIDC. 'production' gates deploys with required reviewers; 'staging' hosts the smoke-gated stage."
  type        = list(string)
  default     = ["production", "staging"]
}

variable "enable_ssm_deploy" {
  description = "Grant the CI/CD deploy role SSM Run Command + EC2 describe permissions used to drive the single-instance Compose stacks (Phase 25)."
  type        = bool
  default     = true
}

variable "ssm_output_bucket" {
  description = "Optional bucket to capture long SSM Run Command output (the pipeline streams output directly when it fits)."
  type        = string
  default     = ""
}