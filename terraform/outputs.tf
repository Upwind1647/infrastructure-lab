output "ec2_public_ip" {
  description = "Public IP of the Bastion server (for SSH)"
  value       = aws_instance.app_server.public_ip
}

output "rds_endpoint" {
  description = "Internal DNS endpoint of the RDS database"
  value       = aws_db_instance.postgres.endpoint
}

output "ssh_command" {
  description = "SSH command to connect to the Bastion server"
  value       = "ssh admin@${aws_instance.app_server.public_ip}"
}

output "db_tunnel_command" {
  description = "SSH tunnel for local database access"
  value       = "ssh -L 5432:${aws_db_instance.postgres.endpoint} admin@${aws_instance.app_server.public_ip}"
}
