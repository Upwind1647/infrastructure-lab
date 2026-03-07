# Debian 13 AMI
data "aws_ami" "debian" {
  most_recent = true
  owners      = ["136693071363"] # Debian AWS Account ID

  filter {
    name   = "name"
    values = ["debian-13-amd64-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# SSH KEY PAIR
resource "aws_key_pair" "deployer" {
  key_name   = "lab-deployer-key"
  public_key = var.ssh_public_key
}

# EC2 INSTANCE (Bastion & App Server)
resource "aws_instance" "app_server" {
  ami           = data.aws_ami.debian.id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public_a.id
  key_name      = aws_key_pair.deployer.key_name

  vpc_security_group_ids = [aws_security_group.app_sg.id]

  # force IMDSv2
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  user_data = <<-EOF
              #!/bin/bash
              set -euo pipefail
              exec > >(tee /var/log/user-data.log) 2>&1

              echo "=== Fetching and executing setup_me.sh ==="
              apt-get update && apt-get install -y curl
              curl -O https://raw.githubusercontent.com/Upwind1647/infrastructure-lab/main/scripts/setup_me.sh
              bash setup_me.sh
              EOF

  user_data_replace_on_change = true

  tags = {
    Name = "app-bastion-server"
    Role = "Compute"
  }
}
