# Download, Upload, Install, and Verify Packages for BIG-IP 1
resource "null_resource" "install_packages_bigip1" {
  depends_on = [aws_instance.bigip, aws_eip.mgmt_eip]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<EOT
      set -e

      # Set Variables per F5 Documentation
      CREDS="${var.bigip_admin_user}:${var.bigip_admin_password}"
      IP="${aws_eip.mgmt_eip[0].public_ip}"

      # ---------------------------------------------------------
      # 1. DECLARATIVE ONBOARDING (DO)
      # ---------------------------------------------------------
      FN_DO="f5-declarative-onboarding-1.47.0-14.noarch.rpm"
      LEN_DO=$(wc -c $FN | cut -f 2 -d ' ')

      echo "Installing DO Package on BIG-IP 1..."
      DATA_DO="{\"operation\":\"INSTALL\",\"packageFilePath\":\"/var/config/rest/downloads/$FN_DO\"}"
      curl -kvu $CREDS "https://$IP/mgmt/shared/iapp/package-management-tasks" \
        -H "Origin: https://$IP" \
        -H 'Content-Type: application/json;charset=UTF-8' \
        --data "$DATA_DO"

      # ---------------------------------------------------------
      # 2. CLOUD FAILOVER EXTENSION (CFE)
      # ---------------------------------------------------------
      FN_CFE="f5-cloud-failover-2.4.0-0.noarch.rpm"
      LEN_CFE=$(wc -c $FN | cut -f 1 -d ' ')

      echo "Installing CFE Package on BIG-IP 1..."
      DATA_CFE="{\"operation\":\"INSTALL\",\"packageFilePath\":\"/var/config/rest/downloads/$FN_CFE\"}"
      curl -kvu $CREDS "https://$IP/mgmt/shared/iapp/package-management-tasks" \
        -H "Origin: https://$IP" \
        -H 'Content-Type: application/json;charset=UTF-8' \
        --data "$DATA_CFE"

      # ---------------------------------------------------------
      # 3. VERIFICATION (Per F5 Docs)
      # ---------------------------------------------------------
      echo "Polling DO Verification API..."
      until curl -sku $CREDS "https://$IP/mgmt/shared/declarative-onboarding/info" | grep -q "version"; do sleep 10; done
      # Save JSON locally for Terraform outputs
      curl -sku $CREDS "https://$IP/mgmt/shared/declarative-onboarding/info" > bigip1_do_info.json

      echo "Polling CFE Verification API..."
      until curl -sku $CREDS "https://$IP/mgmt/shared/cloud-failover/info" | grep -q "version"; do sleep 10; done
      curl -sku $CREDS "https://$IP/mgmt/shared/cloud-failover/info" > bigip1_cfe_info.json

      echo "BIG-IP 1 Packages successfully installed and verified!"
    EOT
  }
}

# Download, Upload, Install, and Verify Packages for BIG-IP 2
resource "null_resource" "install_packages_bigip2" {
  # ADDED DEPENDENCY: Must wait for BIG-IP 1 to finish downloading the RPMs!
  depends_on = [aws_instance.bigip, aws_eip.mgmt_eip, null_resource.install_packages_bigip1]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<EOT
      set -e

      # Set Variables
      CREDS="${var.bigip_admin_user}:${var.bigip_admin_password}"
      IP="${aws_eip.mgmt_eip[1].public_ip}"
      
      # We can reuse the locally downloaded RPM files from BIG-IP 1
      FN_DO="f5-declarative-onboarding-1.47.0-14.noarch.rpm"
      LEN_DO=$(wc -c $FN | cut -f 2 -d ' ')

      echo "Installing DO Package on BIG-IP 2..."
      DATA_DO="{\"operation\":\"INSTALL\",\"packageFilePath\":\"/var/config/rest/downloads/$FN_DO\"}"
      curl -kvu $CREDS "https://$IP/mgmt/shared/iapp/package-management-tasks" \
        -H "Origin: https://$IP" \
        -H 'Content-Type: application/json;charset=UTF-8' \
        --data "$DATA_DO"

      # ---------------------------------------------------------
      # 2. CLOUD FAILOVER EXTENSION (CFE)
      # ---------------------------------------------------------
      FN_CFE="f5-cloud-failover-2.4.0-0.noarch.rpm"    
      LEN_CFE=$(wc -c $FN | cut -f 1 -d ' ')

      echo "Installing CFE Package on BIG-IP 2..."
      DATA_CFE="{\"operation\":\"INSTALL\",\"packageFilePath\":\"/var/config/rest/downloads/$FN_CFE\"}"
      curl -kvu $CREDS "https://$IP/mgmt/shared/iapp/package-management-tasks" \
        -H "Origin: https://$IP" \
        -H 'Content-Type: application/json;charset=UTF-8' \
        --data "$DATA_CFE"

      # Verification
      echo "Polling DO Verification API..."
      until curl -sku $CREDS "https://$IP/mgmt/shared/declarative-onboarding/info" | grep -q "version"; do sleep 10; done
      curl -sku $CREDS "https://$IP/mgmt/shared/declarative-onboarding/info" > bigip2_do_info.json

      echo "Polling CFE Verification API..."
      until curl -sku $CREDS "https://$IP/mgmt/shared/cloud-failover/info" | grep -q "version"; do sleep 10; done
      curl -sku $CREDS "https://$IP/mgmt/shared/cloud-failover/info" > bigip2_cfe_info.json

      echo "BIG-IP 2 Packages successfully installed and verified!"
    EOT
  }
}