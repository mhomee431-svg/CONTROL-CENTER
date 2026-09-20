# ── Inputs — free-tier root module ───────────────────────────────────────────

variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "ap-south-1"
}

# ── Resource tagging (Phase 51) ────────────────────────────────────────────
variable "tag_owner" {
  description = "Owner tag value for cost allocation (e.g. platform-team)."
  type        = string
  default     = "platform-team"
}

variable "tag_cost_center" {
  description = "Cost center tag value (e.g. hyperlocal-001)."
  type        = string
  default     = "hyperlocal-001"
}

variable "tag_project" {
  description = "Project tag value (defaults to project_name)."
  type        = string
  default     = ""
}

variable "project_name" {
  description = "Project prefix for all resources."
  type        = string
  default     = "hyperlocal"
}

variable "environment" {
  description = "Environment (development | staging | production). Environment separation happens through distinct variable files + name prefixes + SSM paths."
  type        = string
  default     = "production"
}

variable "vpc_cidr" {
  description = "VPC CIDR."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Public subnet (app EC2 + Caddy)."
  type        = string
  default     = "10.0.1.0/24"
}

variable "data_subnet_cidr" {
  description = "Isolated data subnet (RDS only — no internet route)."
  type        = string
  default     = "10.0.20.0/24"
}

variable "instance_type" {
  description = "App instance type — t3.micro is the free-tier shape."
  type        = string
  default     = "t3.micro"
}

variable "root_volume_gb" {
  description = "Root EBS size (30GB/mo gp2 is free-tier eligible)."
  type        = number
  default     = 20
}

variable "admin_cidr" {
  description = "Optional CIDR for admin access (e.g. your IP/32). Empty = no admin port."
  type        = string
  default     = ""
}

variable "db_instance_class" {
  description = "RDS instance class — db.t3.micro is the free-tier shape."
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "RDS storage GB (20GB is the free-tier allowance)."
  type        = number
  default     = 20
}

variable "db_name" {
  description = "RDS database name."
  type        = string
  default     = "hyperlocal"
}

variable "db_username" {
  description = "RDS master username."
  type        = string
  default     = "hyperlocal"
}

variable "github_repo" {
  description = "Backend repo URL cloned by the boot script."
  type        = string
  default     = "https://github.com/Akasharyan47/hyperlocal_app.git"
}

variable "github_branch" {
  description = "Branch the boot script deploys."
  type        = string
  default     = "main"
}

variable "domain_name" {
  description = "API domain for Caddy auto-TLS (e.g. api.hyperlocal.in). Empty = plain HTTP on the EIP (no domain / pre-DNS)."
  type        = string
  default     = ""
}

variable "caddy_acme_email" {
  description = "Email address for Let's Encrypt ACME account registration (cert issuance notifications + renewal alerts)."
  type        = string
  default     = ""
}

variable "frontend_domain" {
  description = "Frontend origin for CORS (e.g. app.hyperlocal.in). Used to build CORS_ORIGINS in the boot-generated .env."
  type        = string
  default     = ""
}

variable "admin_frontend_domain" {
  description = "Admin frontend origin for CORS (e.g. admin.hyperlocal.in). Optional."
  type        = string
  default     = ""
}

variable "dns_zone_name" {
  description = "Route53 hosted zone apex for DNS lookups (e.g. hyperlocal.in). Required when manage_dns = true."
  type        = string
  default     = ""
}

variable "manage_dns" {
  description = "Create Route53 A-record pointing api.<domain_name> → app EIP. Set false if DNS is managed externally."
  type        = bool
  default     = true
}

variable "frontend_serve_via_caddy" {
  description = "If true, also create a Route53 CNAME for frontend_domain → EIP (frontend served by Caddy). Most setups serve frontend from S3/CloudFront — leave false."
  type        = bool
  default     = false
}

variable "create_s3_gateway_endpoint" {
  description = "S3 Gateway endpoint (free) for private backend-to-S3 traffic."
  type        = bool
  default     = true
}

variable "enable_vpc_flow_logs" {
  description = "VPC Flow Logs → CloudWatch for the connectivity audit."
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "CloudWatch flow-log retention (1 = cheapest; 14 = sensible)."
  type        = number
  default     = 14
}

variable "flow_log_group_kms" {
  description = "Optional KMS key ARN for the flow-log group (free tier: leave default AWS-managed encryption)."
  type        = string
  default     = null
}

variable "uploads_bucket_name" {
  description = "S3 uploads bucket name. Empty = <project>-<account>-uploads."
  type        = string
  default     = ""
}
