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
  default     = true
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

# FinOps budget guardrails
variable "enable_cost_budget" {
  description = "Create an AWS budget and SNS alerts for spend guardrails"
  type        = bool
  default     = false
}

variable "budget_name" {
  description = "AWS Budget name for monthly spend alerts"
  type        = string
  default     = "infrastructure-lab-monthly-cost"
}

variable "monthly_budget_limit_usd" {
  description = "Monthly budget cap in USD (AWS Budgets supports USD for cost budgets)"
  type        = number
  default     = 55

  validation {
    condition     = var.monthly_budget_limit_usd > 0
    error_message = "monthly_budget_limit_usd must be greater than zero."
  }
}

variable "budget_alert_email" {
  description = "Email endpoint for SNS budget alerts"
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_cost_budget || can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", trimspace(var.budget_alert_email)))
    error_message = "budget_alert_email must be a valid email when enable_cost_budget is true."
  }
}

variable "budget_threshold_warning_percent" {
  description = "Warning alert threshold percentage for AWS Budget notifications"
  type        = number
  default     = 80

  validation {
    condition     = var.budget_threshold_warning_percent > 0 && var.budget_threshold_warning_percent < 100
    error_message = "budget_threshold_warning_percent must be between 1 and 99."
  }
}

variable "budget_threshold_critical_percent" {
  description = "Critical alert threshold percentage for AWS Budget notifications"
  type        = number
  default     = 100

  validation {
    condition     = var.budget_threshold_critical_percent >= 100
    error_message = "budget_threshold_critical_percent must be at least 100."
  }
}

# EKS (Hybrid Hub-and-Spoke)
variable "enable_eks" {
  description = "Enable EKS control plane and managed node group provisioning"
  type        = bool
  default     = false
}

variable "eks_cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "infrastructure-lab-eks-prod"
}

variable "eks_kubeconfig_context_name" {
  description = "Desired kubeconfig context alias for aws eks update-kubeconfig --alias"
  type        = string
  default     = "aws-eks-prod"
}

variable "eks_cluster_version" {
  description = "Kubernetes version for EKS control plane"
  type        = string
  default     = "1.34"
}

variable "eks_node_instance_type" {
  description = "EC2 instance type for EKS managed node group"
  type        = string
  default     = "t3.medium"
}

variable "eks_node_min_size" {
  description = "Minimum EKS node group size"
  type        = number
  default     = 1
}

variable "eks_node_desired_size" {
  description = "Desired EKS node group size"
  type        = number
  default     = 1
}

variable "eks_node_max_size" {
  description = "Maximum EKS node group size"
  type        = number
  default     = 2

  validation {
    condition     = var.eks_node_max_size >= var.eks_node_min_size
    error_message = "eks_node_max_size must be greater than or equal to eks_node_min_size."
  }
}

variable "eks_endpoint_public_access" {
  description = "Expose the EKS API endpoint publicly"
  type        = bool
  default     = true
}

variable "eks_endpoint_private_access" {
  description = "Expose the EKS API endpoint privately inside the VPC"
  type        = bool
  default     = false
}

variable "eks_additional_tags" {
  description = "Additional tags to apply to EKS resources"
  type        = map(string)
  default     = {}
}
