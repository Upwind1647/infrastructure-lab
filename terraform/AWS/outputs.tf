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
