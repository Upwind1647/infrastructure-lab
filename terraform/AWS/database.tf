resource "aws_db_instance" "postgres" {
  identifier     = "infrastructure-lab-db"
  engine         = "postgres"
  engine_version = "18.3"
  instance_class = "db.t3.micro"

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true # Data-at-rest encryption

  db_name  = "appdb"
  username = "dbadmin"
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.data_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  publicly_accessible    = false
  multi_az               = false

  # Backups
  backup_retention_period = 0 # Lab: no backups to minimize cost

  # Maintenance
  auto_minor_version_upgrade = true

  # # Lab kill switch: allows 'terraform destroy' without creating a final snapshot
  skip_final_snapshot = true

  tags = {
    Name = "lab-postgresql"
    Role = "Database"
  }
}
