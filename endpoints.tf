data "aws_region" "current" {}

# S3 Gateway Endpoint
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.route_table_ids
  tags              = { Name = "s3-cfe-endpoint" }
}



# EC2 Interface Endpoint
resource "aws_vpc_endpoint" "ec2" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ec2"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.internal_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
  private_dns_enabled = true 
  tags                = { Name = "ec2-cfe-endpoint" }
}

# S3 Bucket for CFE State
resource "aws_s3_bucket" "cfe_state_bucket" {
  bucket_prefix = "f5-cfe-state-"
  tags = {
    Name                    = "f5-cfe-state-bucket"
    f5_cloud_failover_label = var.cfe_label
  }
}



