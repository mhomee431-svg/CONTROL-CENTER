# ── Resource tagging (Phase 51) ──────────────────────────────────────────────
# Consistent tags on every AWS resource so the Cost Explorer, Terraform state,
# and incident response can group by project / environment / owner.
#
# Standard tags applied to every resource:
#   Project      = hyperlocal
#   Environment  = development | staging | production
#   Owner        = platform-team
#   ManagedBy    = Terraform
#   CostCenter   = hyperlocal-001

locals {
  default_tags = {
    Project     = var.project_name
    Environment = var.environment
    Owner       = "platform-team"
    ManagedBy   = "Terraform"
    CostCenter  = "hyperlocal-001"
  }
}