# Management Security Group
resource "aws_security_group" "mgmt_sg" {
  name        = "bigip-mgmt-sg"
  vpc_id      = var.vpc_id
  description = "Allow Management and SSH traffic"

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.mgmt_allow_ips
  }
  ingress {
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = var.mgmt_allow_ips
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.mgmt_allow_ips
  }

  # --- REQUIRED FOR F5 HA CLUSTER OVER MANAGEMENT ---
  # F5 ConfigSync (Requires TCP 4353)
  ingress {
    from_port   = 4353
    to_port     = 4353
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr] # Allows the BIG-IPs to sync with each other
  }
  # F5 Network Failover Heartbeat (Requires UDP 1026)
  ingress {
    from_port   = 1026
    to_port     = 1026
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr] # Allows the BIG-IPs to ping each other
  }
  # --------------------------------------------------

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "bigip-mgmt-sg" }
}

# External Security Group
resource "aws_security_group" "ext_sg" {
  name        = "bigip-ext-sg"
  vpc_id      = var.vpc_id
  description = "Allow inbound VIP traffic"

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.ext_allow_ips
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.ext_allow_ips
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "bigip-ext-sg" }
}

# Internal Security Group
resource "aws_security_group" "int_sg" {
  name        = "bigip-int-sg"
  vpc_id      = var.vpc_id
  description = "Allow internal VPC traffic"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "bigip-int-sg" }
}

# VPC Endpoint Security Group
resource "aws_security_group" "vpc_endpoint_sg" {
  name        = "vpc-endpoint-sg"
  vpc_id      = var.vpc_id
  description = "Allow CFE API calls from BIG-IPs"

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.mgmt_sg.id, aws_security_group.int_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "vpc-endpoint-sg" }
}