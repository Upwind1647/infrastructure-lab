# General
variable "aws_region" {
  description = "AWS Region for all resources"
  type        = string
  default     = "eu-central-1"
}

variable "instance_type" {
  description = "EC2 instance type for the app/bastion server"
  type        = string
  default     = "t3.micro"
}

# Access
variable "ssh_public_key" {
  description = "SSH public key for EC2 access"
  type        = string
}

variable "home_ip" {
  description = "public IP in CIDR notation for SSH access"
  type        = string

  validation {
    condition     = can(cidrhost(var.home_ip, 0))
    error_message = "home_ip must be valid CIDR"
  }
}

# Database
variable "db_password" {
  description = "Master password for RDS PostgreSQL must be at least 8 characters"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 8
    error_message = "Database password must be at least 8 characters."
  }
}

# OpenTofu state backend bootstrap
variable "enable_tofu_state_backend" {
  description = "Enable one-time bootstrap of S3 and DynamoDB resources used as the OpenTofu remote backend"
  type        = bool
  default     = false
}

variable "tofu_state_bucket_name" {
  description = "Globally unique S3 bucket name for OpenTofu state files"
  type        = string
  default     = ""

  validation {
    condition     = !(var.enable_tofu_state_backend || var.enable_github_actions_oidc) || length(trimspace(var.tofu_state_bucket_name)) > 0
    error_message = "tofu_state_bucket_name must be set when enable_tofu_state_backend or enable_github_actions_oidc is true."
  }
}

variable "tofu_state_lock_table_name" {
  description = "DynamoDB table name used for OpenTofu state locking"
  type        = string
  default     = "infrastructure-lab-tofu-locks"

  validation {
    condition     = !(var.enable_tofu_state_backend || var.enable_github_actions_oidc) || length(trimspace(var.tofu_state_lock_table_name)) > 0
    error_message = "tofu_state_lock_table_name must be set when enable_tofu_state_backend or enable_github_actions_oidc is true."
  }
}

variable "tofu_state_bucket_force_destroy" {
  description = "Allow force-destroy of the OpenTofu state bucket when tearing down the backend"
  type        = bool
  default     = false
}

variable "tofu_state_extra_tags" {
  description = "Additional tags to apply to backend bootstrap resources"
  type        = map(string)
  default     = {}
}

# GitHub Actions OIDC integration for CI-backed OpenTofu runs
variable "enable_github_actions_oidc" {
  description = "Enable IAM resources that allow GitHub Actions to assume an AWS role via OIDC"
  type        = bool
  default     = false
}

variable "create_github_oidc_provider" {
  description = "Create the IAM OIDC provider for GitHub Actions in this AWS account"
  type        = bool
  default     = true
}

variable "github_oidc_provider_arn" {
  description = "Existing IAM OIDC provider ARN to use when create_github_oidc_provider is false"
  type        = string
  default     = ""
}

variable "github_oidc_thumbprint_list" {
  description = "Thumbprints for GitHub Actions OIDC provider"
  type        = list(string)
  default = [
    "1b511abead59c6ce207077c0bf0e0043b1382612",
    "6938fd4d98bab03faadb97b34396831e3780aea1",
  ]
}

variable "github_actions_role_name" {
  description = "IAM role name assumed by GitHub Actions for OpenTofu operations"
  type        = string
  default     = "github-actions-tofu-role"
}

variable "github_actions_sub_allowlist" {
  description = "Allowed OIDC subject patterns (sub claim) for GitHub role assumption"
  type        = list(string)
  default     = ["repo:Upwind1647/infrastructure-lab:*"]

  validation {
    condition     = !var.enable_github_actions_oidc || length(var.github_actions_sub_allowlist) > 0
    error_message = "github_actions_sub_allowlist must not be empty when enable_github_actions_oidc is true."
  }
}
