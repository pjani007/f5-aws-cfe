resource "null_resource" "deploy_cfe_bigip1" {
  depends_on = [
    aws_instance.bigip,
    aws_network_interface_attachment.ext_attach,
    aws_network_interface_attachment.int_attach,
    aws_ec2_tag.route_table_tag,
    aws_vpc_endpoint.ec2,
    aws_vpc_endpoint.s3,
    aws_s3_bucket.cfe_state_bucket,
    null_resource.deploy_do_bigip1,
    null_resource.deploy_do_bigip2
  ]
  triggers = {
    declaration = jsonencode(local.cfe_declaration)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]

    command = <<-EOT
      echo "Waiting for CFE endpoint on BIG-IP 1..."
      until curl -sk -u '${var.bigip_admin_user}:${var.bigip_admin_password}' \
        https://${aws_eip.mgmt_eip[0].public_ip}/mgmt/shared/cloud-failover/info \
        | grep -q "version"; do
          echo "CFE not ready yet, retrying..."
          sleep 15
      done

      printf '%s' '${replace(jsonencode(local.cfe_declaration), "'", "'\\''")}' > cfe_payload1.json

      echo "Pushing CFE Declaration to BIG-IP 1..."
      curl -sk -u '${var.bigip_admin_user}:${var.bigip_admin_password}' \
        -X POST https://${aws_eip.mgmt_eip[0].public_ip}/mgmt/shared/cloud-failover/declare \
        -H "Content-Type: application/json" \
        -d @cfe_payload1.json

      echo "Verifying CFE Declaration on BIG-IP 1..."
      until curl -sk -u '${var.bigip_admin_user}:${var.bigip_admin_password}' \
        -X GET https://${aws_eip.mgmt_eip[0].public_ip}/mgmt/shared/cloud-failover/declare \
        | grep -q '"class":"Cloud_Failover"'; do
          echo "CFE not yet applied, retrying..."
          sleep 10
      done

      echo "BIG-IP 1 CFE Deployed and Verified!"
    EOT
  }
}

resource "null_resource" "deploy_cfe_bigip2" {
  depends_on = [
    aws_instance.bigip,
    aws_network_interface_attachment.ext_attach,
    aws_network_interface_attachment.int_attach,
    aws_ec2_tag.route_table_tag,
    aws_vpc_endpoint.ec2,
    aws_vpc_endpoint.s3,
    aws_s3_bucket.cfe_state_bucket,
    null_resource.deploy_do_bigip1,
    null_resource.deploy_do_bigip2,
    null_resource.deploy_cfe_bigip1  # ← sequential, not parallel
  ]
  triggers = {
    declaration = jsonencode(local.cfe_declaration)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]

    command = <<-EOT
      echo "Waiting for CFE endpoint on BIG-IP 2..."
      until curl -sk -u '${var.bigip_admin_user}:${var.bigip_admin_password}' \
        https://${aws_eip.mgmt_eip[1].public_ip}/mgmt/shared/cloud-failover/info \
        | grep -q "version"; do
          echo "CFE not ready yet, retrying..."
          sleep 15
      done

      printf '%s' '${replace(jsonencode(local.cfe_declaration), "'", "'\\''")}' > cfe_payload2.json

      echo "Pushing CFE Declaration to BIG-IP 2..."
      curl -sk -u '${var.bigip_admin_user}:${var.bigip_admin_password}' \
        -X POST https://${aws_eip.mgmt_eip[1].public_ip}/mgmt/shared/cloud-failover/declare \
        -H "Content-Type: application/json" \
        -d @cfe_payload2.json

      echo "Verifying CFE Declaration on BIG-IP 2..."
      until curl -sk -u '${var.bigip_admin_user}:${var.bigip_admin_password}' \
        -X GET https://${aws_eip.mgmt_eip[1].public_ip}/mgmt/shared/cloud-failover/declare \
        | grep -q '"class":"Cloud_Failover"'; do
          echo "CFE not yet applied, retrying..."
          sleep 10
      done

      echo "BIG-IP 2 CFE Deployed and Verified!"
    EOT
  }
}