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
