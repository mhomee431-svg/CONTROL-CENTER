# ── Iner Infrastructure — input variables ─────────────────────────────────
# Fill real values in terraform.tfvars or via -var. Secrets are NEVER here.

variable "aws_region" {
  description = "AWS region for the deployment."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Resource prefix (lowercase, hyphens allowed)."
  type        = string
  default     = "hyperlocal"
}

variable "environment" {
  description = "Deployment stage (staging | production)."
  type        = string
  default     = "staging"
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default = {
    Project = "hyperlocal_customer_app"
    Owner   = "your-email@example.com"
  }
}

# ── Networking ──────────────────────────────────────────────────────────────
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "availability_zones" {
  type        = list(string)
  description = ">=2 subnets designed to be in distinct AZs."
  default     = ["us-east-1a", "us-east-1b"]
}

# ── Compute / ECS ───────────────────────────────────────────────────────────
variable "backend_image_tag" {
  type    = string
  default = "latest"
}

variable "app_port" {
  type    = number
  default = 8000
}

variable "app_cpu" {
  type    = number
  default = 512
}

variable "app_memory" {
  type    = number
  default = 1024
}

variable "worker_desired_count" {
  type    = number
  default = 1
}

variable "desired_count" {
  type    = number
  default = 2
}

variable "min_capacity" {
  type    = number
  default = 1
}

variable "max_capacity" {
  type    = number
  default = 4
}

# ── RDS ─────────────────────────────────────────────────────────────────────
variable "database_name" {
  type    = string
  default = "hyperlocal"
}

variable "database_instance_class" {
  type    = string
  default = "db.t3.small"
}

variable "database_allocated_storage" {
  type    = number
  default = 20
}

variable "database_multi_az" {
  type    = bool
  default = false
}

variable "backup_retention_days" {
  type    = number
  default = 7
}

# ── Redis ───────────────────────────────────────────────────────────────────
variable "redis_node_type" {
  type    = string
  default = "cache.t3.micro"
}

variable "redis_num_cache_nodes" {
  type    = number
  default = 1
}

# ── Domain / HTTPS ──────────────────────────────────────────────────────────
variable "domain_name" {
  description = "Root domain for API hosting (e.g. example.com)."
  type        = string
  default     = "example.com"
}

variable "api_subdomain" {
  type    = string
  default = "api"
}

variable "create_acm_certificate" {
  type    = bool
  default = true
}

variable "acm_certificate_arn" {
  type    = string
  default = ""
}

variable "create_route53_records" {
  type    = bool
  default = false
}

# ── Container registry / secrets ────────────────────────────────────────────
variable "ecr_registry_url" {
  description = "ECR registry base (123456789012.dkr.ecr.us-east-1.amazonaws.com)."
  type        = string
  default     = "REPLACE_WITH_ECR_REGISTRY"
}

variable "ecr_repository_name" {
  type    = string
  default = "hyperlocal-backend"
}

variable "ecs_cluster_name" {
  type    = string
  default = "hyperlocal-cluster"
}

variable "use_aws_secrets" {
  type    = bool
  default = true
}

variable "secrets_secret_name" {
  type    = string
  default = "hyperlocal"
}

variable "is_production" {
  type    = bool
  default = false
}

variable "hosted_zone_id" {
  description = "Route53 hosted zone ID for domain_name (used for DNS validation + A record)."
  type        = string
  default     = ""
}