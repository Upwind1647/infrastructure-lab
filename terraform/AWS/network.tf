# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.200.0.0/20" # 4.096 IPs (10.200.0.0 – 10.200.15.255)
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "main-lab-vpc"
  }
}

# Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "main-igw" }
}

# Public Subnets (Ingress Layer -> Bastion / Load Balancer)
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.200.8.0/24" # 256 IPs
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-a"
    Tier = "Public"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "public-route-table" }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_rt.id
}

# Private Subnets (Application Layer -> K3s / App Workloads)
# No internet access without a NAT Gateway
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.200.0.0/21" # 2.048 IPs
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "private-subnet-a"
    Tier = "Private"
  }
}

# Explicit Route Table: VPC-internal routing only, no internet access
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id

  # No 0.0.0.0/0 route = no internet access
  # For internet access: add a NAT Gateway (~$32/month)

  tags = { Name = "private-route-table" }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private_rt.id
}

# Data Subnets (Persistence Layer — RDS)
# AWS RDS Subnet Groups require subnets in at least 2 AZs
resource "aws_subnet" "data_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.200.9.0/24" # 256 IPs
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "data-subnet-a"
    Tier = "Data"
  }
}

resource "aws_subnet" "data_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.200.11.0/24" # 256 IPs
  availability_zone = "${var.aws_region}b"

  tags = {
    Name = "data-subnet-b"
    Tier = "Data"
  }
}

resource "aws_db_subnet_group" "data_group" {
  name       = "main-data-subnet-group"
  subnet_ids = [aws_subnet.data_a.id, aws_subnet.data_b.id]

  tags = { Name = "data-subnet-group" }
}
