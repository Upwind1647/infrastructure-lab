data "aws_caller_identity" "observability" {
  count = var.enable_eks ? 1 : 0
}

data "archive_file" "status_api_canary" {
  count = var.enable_eks ? 1 : 0

  type = "zip"

  source {
    content  = file("${path.module}/scripts/canary-status-api.js")
    filename = "nodejs/node_modules/index.js"
  }

  output_path = "${path.module}/.terraform/status-api-canary.zip"
}

resource "aws_s3_bucket" "synthetics_artifacts" {
  count = var.enable_eks ? 1 : 0

  bucket        = "infrastructure-lab-synthetics-${data.aws_caller_identity.observability[0].account_id}-${var.aws_region}"
  force_destroy = true

  tags = {
    Name      = "infrastructure-lab-synthetics-artifacts"
    Purpose   = "CloudWatch Synthetics run artifacts"
    CostModel = "WeekendLifecycle"
  }
}

resource "aws_s3_bucket_versioning" "synthetics_artifacts" {
  count = var.enable_eks ? 1 : 0

  bucket = aws_s3_bucket.synthetics_artifacts[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "synthetics_artifacts" {
  count = var.enable_eks ? 1 : 0

  bucket = aws_s3_bucket.synthetics_artifacts[0].bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "synthetics_artifacts" {
  count = var.enable_eks ? 1 : 0

  bucket = aws_s3_bucket.synthetics_artifacts[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_role" "synthetics_canary" {
  count = var.enable_eks ? 1 : 0

  name = "${var.eks_cluster_name}-synthetics-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  lifecycle {
    precondition {
      condition     = var.enable_cost_budget
      error_message = "enable_cost_budget must be true before enable_eks can provision CloudWatch canaries."
    }
  }
}

resource "aws_iam_role_policy" "synthetics_canary" {
  count = var.enable_eks ? 1 : 0

  name = "${var.eks_cluster_name}-synthetics-policy"
  role = aws_iam_role.synthetics_canary[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",
          "s3:ListAllMyBuckets",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = [
          "${aws_s3_bucket.synthetics_artifacts[0].arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_synthetics_canary" "status_api" {
  count = var.enable_eks ? 1 : 0

  name                 = "${var.eks_cluster_name}-status-api"
  artifact_s3_location = "s3://${aws_s3_bucket.synthetics_artifacts[0].bucket}/artifacts/"
  execution_role_arn   = aws_iam_role.synthetics_canary[0].arn
  handler              = "index.handler"
  runtime_version      = "syn-nodejs-puppeteer-9.1"
  zip_file             = data.archive_file.status_api_canary[0].output_path
  start_canary         = true

  success_retention_period = 7
  failure_retention_period = 14

  schedule {
    expression = "rate(1 hour)"
  }

  run_config {
    timeout_in_seconds = 14
    environment_variables = {
      URL_LAB   = "https://northlift.net"
      URL_CLOUD = "https://aws.northlift.net"
    }
  }

  tags = {
    Name      = "${var.eks_cluster_name}-status-api"
    Purpose   = "External uptime probes"
    CostModel = "WeekendLifecycle"
  }
}

resource "aws_cloudwatch_metric_alarm" "status_api_success_percent" {
  count = var.enable_eks ? 1 : 0

  alarm_name          = "${var.eks_cluster_name}-canary-success-percent"
  alarm_description   = "Alert when canary success percent falls below 100 over two datapoints"
  comparison_operator = "LessThanThreshold"
  threshold           = 100

  evaluation_periods  = 2
  datapoints_to_alarm = 2
  period              = 3600
  statistic           = "Average"
  treat_missing_data  = "breaching"

  namespace   = "CloudWatchSynthetics"
  metric_name = "SuccessPercent"

  dimensions = {
    CanaryName = aws_synthetics_canary.status_api[0].name
  }

  alarm_actions = var.enable_cost_budget ? [aws_sns_topic.budget_alerts[0].arn] : []
}

resource "aws_cloudwatch_metric_alarm" "status_api_duration" {
  count = var.enable_eks ? 1 : 0

  alarm_name          = "${var.eks_cluster_name}-canary-duration"
  alarm_description   = "Alert when canary duration exceeds 5000ms over two datapoints"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 5000

  evaluation_periods  = 2
  datapoints_to_alarm = 2
  period              = 3600
  statistic           = "Average"
  treat_missing_data  = "notBreaching"

  namespace   = "CloudWatchSynthetics"
  metric_name = "Duration"

  dimensions = {
    CanaryName = aws_synthetics_canary.status_api[0].name
  }

  alarm_actions = var.enable_cost_budget ? [aws_sns_topic.budget_alerts[0].arn] : []
}

resource "aws_s3_bucket_lifecycle_configuration" "synthetics_artifacts" {
  count  = var.enable_eks ? 1 : 0
  bucket = aws_s3_bucket.synthetics_artifacts[0].id

  rule {
    id     = "expire-canary-artifacts"
    status = "Enabled"

    filter {}

    expiration {
      days = 14
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}
