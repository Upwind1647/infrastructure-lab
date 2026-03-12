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
