output "ec2_public_ip" {
  description = "Public IP des Bastion Servers (für SSH)"
  value       = aws_instance.app_server.public_ip
}

output "rds_endpoint" {
  description = "Interner DNS-Endpoint der RDS Datenbank"
  value       = aws_db_instance.postgres.endpoint
}

output "ssh_command" {
  description = "SSH-Befehl zum Verbinden mit dem Bastion Server"
  value       = "ssh admin@${aws_instance.app_server.public_ip}"
}

output "db_tunnel_command" {
  description = "SSH Tunnel für lokalen DB-Zugriff"
  value       = "ssh -L 5432:${aws_db_instance.postgres.endpoint} admin@${aws_instance.app_server.public_ip}"
}
