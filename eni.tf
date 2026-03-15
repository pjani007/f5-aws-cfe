# Management Interfaces
resource "aws_network_interface" "mgmt" {
  count             = 2
  subnet_id         = var.mgmt_subnet_ids[count.index]
  # Use a conditional to pick the right string variable for mgmt
  private_ips       = [count.index == 0 ? var.bigip1_mgmt_ip : var.bigip2_mgmt_ip] 
  security_groups   = [aws_security_group.mgmt_sg.id]
  source_dest_check = true 
  
  tags = {
    Name = "bigip-${count.index + 1}-mgmt"
  }
}

# External Interfaces
resource "aws_network_interface" "external" {
  count             = 2
  subnet_id         = var.ext_subnet_ids[count.index]
  # Force AWS to use the exact IPs from your list
  private_ips       = [var.bigip_external_self_ips[count.index]] 
  security_groups   = [aws_security_group.ext_sg.id]
  source_dest_check = false 

  tags = {
    Name = "bigip-${count.index + 1}-ext"
  }
}

# Internal Interfaces
resource "aws_network_interface" "internal" {
  count             = 2
  subnet_id         = var.int_subnet_ids[count.index]
  # Force AWS to use the exact IPs from your list
  private_ips       = [var.bigip_internal_self_ips[count.index]] 
  security_groups   = [aws_security_group.int_sg.id]
  source_dest_check = false 

  tags = {
    Name = "bigip-${count.index + 1}-int"
  }
}