# ── Inputs — free-tier root module ───────────────────────────────────────────

variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "ap-south-1"
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
  default     = "https://github.com/Akasharyan47/hyperlocal_customer_app.git"
}

variable "github_branch" {
  description = "Branch the boot script deploys."
  type        = string
  default     = "main"
}

variable "domain_name" {
  description = "Root domain for Caddy auto-TLS. Empty = plain HTTP on the EIP."
  type        = string
  default     = ""
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
