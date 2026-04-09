# Optional backend bootstrap for CI-driven OpenTofu modules.
# Keep this disabled for normal lab applies unless you are provisioning
# remote state infrastructure for automation workflows.
resource "aws_s3_bucket" "tofu_state" {
  count = var.enable_tofu_state_backend ? 1 : 0

  bucket        = var.tofu_state_bucket_name
  force_destroy = var.tofu_state_bucket_force_destroy

  tags = merge(
    {
      Name      = "infrastructure-lab-tofu-state"
      ManagedBy = "Terraform"
      Purpose   = "OpenTofu remote state backend"
    },
    var.tofu_state_extra_tags,
  )
}

resource "aws_s3_bucket_versioning" "tofu_state" {
  count = var.enable_tofu_state_backend ? 1 : 0

  bucket = aws_s3_bucket.tofu_state[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tofu_state" {
  count = var.enable_tofu_state_backend ? 1 : 0

  bucket = aws_s3_bucket.tofu_state[0].bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tofu_state" {
  count = var.enable_tofu_state_backend ? 1 : 0

  bucket = aws_s3_bucket.tofu_state[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tofu_state_locks" {
  count = var.enable_tofu_state_backend ? 1 : 0

  name         = var.tofu_state_lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = merge(
    {
      Name      = "infrastructure-lab-tofu-lock-table"
      ManagedBy = "Terraform"
      Purpose   = "OpenTofu state locking"
    },
    var.tofu_state_extra_tags,
  )
}

data "aws_caller_identity" "current" {
  count = var.enable_github_actions_oidc ? 1 : 0
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.enable_github_actions_oidc && var.create_github_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = var.github_oidc_thumbprint_list
}

locals {
  github_oidc_provider_arn = var.enable_github_actions_oidc ? (
    var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.github_oidc_provider_arn
  ) : null
}

resource "aws_iam_role" "github_actions_tofu" {
  count = var.enable_github_actions_oidc ? 1 : 0

  name = var.github_actions_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = local.github_oidc_provider_arn
        }
        Condition = {
          "ForAnyValue:StringLike" = {
            "token.actions.githubusercontent.com:sub" = var.github_actions_sub_allowlist
          }
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  lifecycle {
    precondition {
      condition     = var.create_github_oidc_provider || length(trimspace(var.github_oidc_provider_arn)) > 0
      error_message = "Set github_oidc_provider_arn when create_github_oidc_provider is false."
    }
  }
}

resource "aws_iam_role_policy" "github_actions_tofu_policy" {
  count = var.enable_github_actions_oidc ? 1 : 0

  name = "tofu-state-access"
  role = aws_iam_role.github_actions_tofu[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:List*",
          "s3:Get*"
        ]
        Resource = [
          "arn:aws:s3:::${var.tofu_state_bucket_name}",
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = [
          "arn:aws:s3:::${var.tofu_state_bucket_name}/*",
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeTable",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:UpdateItem",
          "dynamodb:DescribeContinuousBackups",
          "dynamodb:DescribeTimeToLive",
          "dynamodb:ListTagsOfResource",
        ]
        Resource = [
          "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current[0].account_id}:table/${var.tofu_state_lock_table_name}",
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:Describe*",
          "budgets:ViewBudget",
          "budgets:ListTagsForResource",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListTagsForResource",
          "ec2:Describe*",
          "eks:Describe*",
          "eks:List*",
          "elasticloadbalancing:Describe*",
          "iam:Get*",
          "iam:List*",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "rds:Describe*",
          "rds:ListTagsForResource",
          "resourcegroupstaggingapi:GetResources",
          "s3:GetBucketLocation",
          "s3:GetBucketPolicyStatus",
          "s3:GetBucketPublicAccessBlock",
          "s3:GetBucketVersioning",
          "s3:GetEncryptionConfiguration",
          "s3:ListBucket",
          "sns:GetTopicAttributes",
          "sns:GetSubscriptionAttributes",
          "sns:ListSubscriptionsByTopic",
          "sns:ListTagsForResource",
          "synthetics:Describe*",
          "synthetics:Get*",
          "synthetics:List*",
          "sts:GetCallerIdentity",
        ]
        Resource = "*"
      },
    ]
  })

  lifecycle {
    precondition {
      condition     = length(trimspace(var.tofu_state_bucket_name)) > 0
      error_message = "tofu_state_bucket_name must be set when enable_github_actions_oidc is true."
    }

    precondition {
      condition     = length(trimspace(var.tofu_state_lock_table_name)) > 0
      error_message = "tofu_state_lock_table_name must be set when enable_github_actions_oidc is true."
    }
  }
}
