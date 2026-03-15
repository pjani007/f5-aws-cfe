# Tag Route Tables
resource "aws_ec2_tag" "route_table_tag" {
  count       = length(var.route_table_ids)
  resource_id = var.route_table_ids[count.index]
  key         = "f5_cloud_failover_label"
  value       = var.cfe_label
}