output "ec2_public_ip" {
  description = "Public IP of the bastion server"
  value       = aws_instance.app_server.public_ip
}

output "rds_endpoint" {
  description = "Internal DNS name of the RDS database"
  value       = aws_db_instance.postgres.address
}

output "ssh_command" {
  description = "SSH command to connect"
  value       = "ssh adminsetup@${aws_instance.app_server.public_ip}"
}

output "db_tunnel_command" {
  description = "SSH tunnel for local DB access"
  value       = "ssh -L 5432:${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port} adminsetup@${aws_instance.app_server.public_ip}"
}

output "tofu_state_backend_enabled" {
  description = "Whether backend bootstrap resources were enabled for this apply"
  value       = var.enable_tofu_state_backend
}

output "tofu_state_bucket_name" {
  description = "S3 bucket name for OpenTofu remote state"
  value       = try(aws_s3_bucket.tofu_state[0].id, null)
}

output "tofu_state_lock_table_name" {
  description = "DynamoDB lock table name for OpenTofu remote state locking"
  value       = try(aws_dynamodb_table.tofu_state_locks[0].name, null)
}

output "tofu_state_backend_region" {
  description = "AWS region that hosts the OpenTofu remote backend resources"
  value       = var.aws_region
}

output "github_oidc_provider_arn" {
  description = "IAM OIDC provider ARN used by GitHub Actions"
  value       = local.github_oidc_provider_arn
}

output "github_actions_role_arn" {
  description = "IAM role ARN to set in GitHub variable AWS_ROLE_TO_ASSUME"
  value       = try(aws_iam_role.github_actions_tofu[0].arn, null)
}

output "budget_name" {
  description = "AWS Budget name used for monthly FinOps guardrails"
  value       = try(aws_budgets_budget.monthly[0].name, null)
}

output "budget_alert_sns_topic_arn" {
  description = "SNS topic ARN that receives AWS Budget threshold notifications"
  value       = try(aws_sns_topic.budget_alerts[0].arn, null)
}

output "synthetics_canary_name" {
  description = "CloudWatch Synthetics canary name"
  value       = try(aws_synthetics_canary.status_api[0].name, null)
}

output "synthetics_canary_arn" {
  description = "CloudWatch Synthetics canary ARN"
  value       = try(aws_synthetics_canary.status_api[0].arn, null)
}

output "synthetics_alarm_success_percent_name" {
  description = "CloudWatch alarm name for canary SuccessPercent"
  value       = try(aws_cloudwatch_metric_alarm.status_api_success_percent[0].alarm_name, null)
}

output "synthetics_alarm_duration_name" {
  description = "CloudWatch alarm name for canary Duration"
  value       = try(aws_cloudwatch_metric_alarm.status_api_duration[0].alarm_name, null)
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = try(aws_eks_cluster.main[0].name, null)
}

output "eks_cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = try(aws_eks_cluster.main[0].endpoint, null)
}

output "eks_cluster_ca_certificate" {
  description = "EKS cluster certificate authority data (base64)"
  value       = try(aws_eks_cluster.main[0].certificate_authority[0].data, null)
  sensitive   = true
}

output "eks_kubeconfig_context_name" {
  description = "Kubeconfig context alias to register with ArgoCD"
  value       = var.eks_kubeconfig_context_name
}

output "eks_oidc_provider_arn" {
  description = "IAM OIDC provider ARN for IRSA"
  value       = try(aws_iam_openid_connect_provider.eks[0].arn, null)
}

output "eks_admin_access_key" {
  description = "IAM Access Key for EKS Admin"
  value       = try(aws_iam_access_key.eks_admin[0].id, null)
}

output "eks_admin_secret_key" {
  description = "IAM Secret Key for EKS Admin"
  value       = try(aws_iam_access_key.eks_admin[0].secret, null)
  sensitive   = true
}
