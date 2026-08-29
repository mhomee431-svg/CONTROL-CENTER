# infra/free/variables.tf
# Free-tier single-instance deployment inputs.
#
# Everything defaults to the cheapest workable option in ap-south-1.
# See docs/FREE_TIER_CLOUD.md for the cost math and upgrade path.

variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Short project tag used in resource names."
  type        = string
  default     = "hyperlocal"
}

variable "instance_type" {
  description = "Free-tier eligible instance type. t3.micro OR t2.micro are 750h free-tier eligible."
  type        = string
  default     = "t3.micro"
}

variable "root_volume_gb" {
  description = "Root EBS size (gp3). 30GB keeps docker images + database comfortable."
  type        = number
  default     = 20
}

variable "github_repo" {
  description = "Repository cloned onto the instance at boot."
  type        = string
  default     = "https://github.com/Akasharyan47/hyperlocal_customer_app.git"
}

variable "github_branch" {
  description = "Branch checked out on the instance."
  type        = string
  default     = "main"
}

variable "admin_cidr" {
  description = <<EOT
Optional CIDR allowed extra ingress (e.g. your office IP "203.0.113.5/32").
Port 80 stays world-open for the app itself regardless.
EOT
  type        = string
  default     = ""
}
