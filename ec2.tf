resource "aws_instance" "bigip" {
  count         = 2
  ami           = var.f5_ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  iam_instance_profile = aws_iam_instance_profile.bigip_profile.name
  depends_on = [
    aws_iam_instance_profile.bigip_profile,
    aws_vpc_endpoint.s3,
    aws_vpc_endpoint.ec2,
    aws_s3_bucket.cfe_state_bucket,
    aws_eip.mgmt_eip
  ]
  # 1. Primary Network Interface (Management - Index 0)
  network_interface {
    network_interface_id = aws_network_interface.mgmt[count.index].id
    device_index = 0
  }
  user_data = templatefile("${path.module}/templates/f5_onboard.sh", {
    license_key = var.license_keys[count.index]
    do_url               = var.do_url 
    cfe_url              = var.cfe_url
    admin_pass  = var.bigip_admin_password
  })
  tags = {
    Name = "f5-bigip-${count.index + 1}"
  }
}

# 2. Attach External Interface (Index 1)
resource "aws_network_interface_attachment" "ext_attach" {
  count                = 2
  instance_id          = aws_instance.bigip[count.index].id
  network_interface_id = aws_network_interface.external[count.index].id
  device_index         = 1
  depends_on = [aws_instance.bigip]
}

# 3. Attach Internal Interface (Index 2)
resource "aws_network_interface_attachment" "int_attach" {
  count                = 2
  instance_id          = aws_instance.bigip[count.index].id
  network_interface_id = aws_network_interface.internal[count.index].id
  device_index         = 2
  depends_on = [aws_instance.bigip]
}