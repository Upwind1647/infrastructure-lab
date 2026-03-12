# APP / BASTION SECURITY GROUP
resource "aws_security_group" "app_sg" {
  name        = "app-bastion-sg"
  description = "Allow HTTP/HTTPS from anywhere, SSH from Home IP only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from Home IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.home_ip]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "app-bastion-sg" }
}

# RDS Security Group
resource "aws_security_group" "rds_sg" {
  name        = "rds-postgres-sg"
  description = "Allow PostgreSQL from App Security Group only"
  vpc_id      = aws_vpc.main.id

  # Only access: from the Bastion/App Server
  # For local DB access: use SSH tunnel
  #   ssh -L 5432:<rds-endpoint>:5432 admin@<bastion-ip>
  ingress {
    description     = "PostgreSQL from App Server"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "rds-postgres-sg" }
}
