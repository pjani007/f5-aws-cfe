locals {
  # BIG-IP 1: Networking, HA Trust, and Device Group
  do_payload_bigip1 = {
    schemaVersion = "1.0.0"
    class         = "Device"
    async         = true
    Common = {
      class    = "Tenant"
      mySystem = { class = "System", hostname = "bigip1.local" }
      ext_vlan = { class = "VLAN", interfaces = [{ name = "1.1", tagged = false }] }
      int_vlan = { class = "VLAN", interfaces = [{ name = "1.2", tagged = false }] }
      ntp = {
        class    = "NTP"
        servers  = ["169.254.169.123"]
        timezone = "UTC"
      }

      ext_self        = { class = "SelfIp", address = "${var.bigip_external_self_ips[0]}/24", vlan = "ext_vlan", allowService = "default" }
      int_self        = { class = "SelfIp", address = "${var.bigip_internal_self_ips[0]}/24", vlan = "int_vlan", allowService = "default" }

      configsync      = { class = "ConfigSync", configsyncIp = var.bigip_internal_self_ips[0] }
      failoverAddress = { class = "FailoverUnicast", address = var.bigip_internal_self_ips[0], port = 1026 }

      vpc_route = {
        class   = "Route"
        network = var.vpc_cidr
        gw      = var.bigip_int_gws[0]   # ← 10.0.160.1
        localOnly = true
      }
      failoverGroup = {
        class           = "DeviceGroup"
        type            = "sync-failover"
        members         = ["bigip1.local", "bigip2.local"]
        owner           = "bigip1.local"
        autoSync        = true
        networkFailover = true
      }
      trust = {
        class          = "DeviceTrust"
        localUsername  = "admin"
        localPassword  = var.bigip_admin_password
        remoteHost = var.bigip1_mgmt_ip
        remoteUsername = "admin"
        remotePassword = var.bigip_admin_password
      }
    }
  }

  # BIG-IP 2: Networking Only
  do_payload_bigip2 = {
    schemaVersion = "1.0.0"
    class         = "Device"
    async         = true
    Common = {
      class    = "Tenant"
      mySystem = { class = "System", hostname = "bigip2.local" }
      ext_vlan = { class = "VLAN", interfaces = [{ name = "1.1", tagged = false }] }
      int_vlan = { class = "VLAN", interfaces = [{ name = "1.2", tagged = false }] }
      ntp = {
        class    = "NTP"
        servers  = ["169.254.169.123"]
        timezone = "UTC"
      }
      vpc_route = {
        class   = "Route"
        network = var.vpc_cidr
        gw      = var.bigip_int_gws[1]   # ← 10.0.176.1
        localOnly = true
      }
      ext_self        = { class = "SelfIp", address = "${var.bigip_external_self_ips[1]}/24", vlan = "ext_vlan", allowService = "default" }
      int_self        = { class = "SelfIp", address = "${var.bigip_internal_self_ips[1]}/24", vlan = "int_vlan", allowService = "default" }

      configsync      = { class = "ConfigSync", configsyncIp = var.bigip_internal_self_ips[1] }
      failoverAddress = { class = "FailoverUnicast", address = var.bigip_internal_self_ips[1], port = 1026 }
    }
  }
}

# outputs.tf additions needed - save task IDs for output
resource "null_resource" "deploy_do_bigip2" {
  depends_on = [aws_instance.bigip, null_resource.install_packages_bigip2]
  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for DO endpoint on BIG-IP 2..."
      until curl -sk -u '${var.bigip_admin_user}:${var.bigip_admin_password}' \
        https://${aws_eip.mgmt_eip[1].public_ip}/mgmt/shared/declarative-onboarding/info \
        | grep -q "version"; do
          echo "DO not ready yet, retrying..."
          sleep 15
      done

      printf '%s' '${replace(jsonencode(local.do_payload_bigip2), "'", "'\\''")}' > do_payload2.json

      echo "Pushing DO Declaration to BIG-IP 2..."
      curl -sk -u '${var.bigip_admin_user}:${var.bigip_admin_password}' \
        -X POST https://${aws_eip.mgmt_eip[1].public_ip}/mgmt/shared/declarative-onboarding \
        -H "Content-Type: application/json" \
        -d @do_payload2.json

      echo "Polling Async Task Status for BIG-IP 2..."
      until curl -sk -u '${var.bigip_admin_user}:${var.bigip_admin_password}' \
        -X GET https://${aws_eip.mgmt_eip[1].public_ip}/mgmt/shared/declarative-onboarding/task \
        | grep -qE '"message":"success"|"status":"FINISHED"'; do
          echo "Waiting for DO to apply..."
          sleep 10
      done

      # Save final DO task result
      curl -sk -u '${var.bigip_admin_user}:${var.bigip_admin_password}' \
        -X GET https://${aws_eip.mgmt_eip[1].public_ip}/mgmt/shared/declarative-onboarding/task \
        > bigip2_do_task.json

      echo "BIG-IP 2 Networking Configured!"
    EOT
  }
}

resource "null_resource" "deploy_do_bigip1" {
  depends_on = [null_resource.deploy_do_bigip2, null_resource.install_packages_bigip1]
  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for DO endpoint on BIG-IP 1..."
      until curl -sk -u '${var.bigip_admin_user}:${var.bigip_admin_password}' \
        https://${aws_eip.mgmt_eip[0].public_ip}/mgmt/shared/declarative-onboarding/info \
        | grep -q "version"; do
          echo "DO not ready yet, retrying..."
          sleep 15
      done

      printf '%s' '${replace(jsonencode(local.do_payload_bigip1), "'", "'\\''")}' > do_payload1.json

      echo "Pushing DO Declaration to BIG-IP 1..."
      curl -sk -u '${var.bigip_admin_user}:${var.bigip_admin_password}' \
        -X POST https://${aws_eip.mgmt_eip[0].public_ip}/mgmt/shared/declarative-onboarding \
        -H "Content-Type: application/json" \
        -d @do_payload1.json

      echo "Polling Async Task Status for BIG-IP 1 HA Cluster..."
      until curl -sk -u '${var.bigip_admin_user}:${var.bigip_admin_password}' \
        -X GET https://${aws_eip.mgmt_eip[0].public_ip}/mgmt/shared/declarative-onboarding/task \
        | grep -qE '"message":"success"|"status":"FINISHED"'; do
          echo "Waiting for DO to apply and Cluster to build..."
          sleep 10
      done

      # Save final DO task result
      curl -sk -u '${var.bigip_admin_user}:${var.bigip_admin_password}' \
        -X GET https://${aws_eip.mgmt_eip[0].public_ip}/mgmt/shared/declarative-onboarding/task \
        > bigip1_do_task.json

      echo "BIG-IP 1 HA Cluster Configured!"
    EOT
  }
}

# ── Config Sync trigger after both DOs complete ───────────────────────────────
resource "null_resource" "trigger_config_sync" {
  depends_on = [null_resource.deploy_do_bigip1, null_resource.deploy_do_bigip2]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for BIG-IP 1 REST API before config-sync..."
      until curl -sk -u '${var.bigip_admin_user}:${var.bigip_admin_password}' \
        https://${aws_eip.mgmt_eip[0].public_ip}/mgmt/tm/sys/version \
        | grep -q "version"; do
          sleep 15
      done

      echo "Triggering config-sync from BIG-IP 1 to failoverGroup..."
      curl -sk -u '${var.bigip_admin_user}:${var.bigip_admin_password}' \
        -X POST https://${aws_eip.mgmt_eip[0].public_ip}/mgmt/tm/cm \
        -H "Content-Type: application/json" \
        -d '{"command":"run","utilCmdArgs":"config-sync to-group failoverGroup"}'

      echo "Waiting 30s for sync to propagate..."
      sleep 30

      echo "Verifying device group sync status..."
      curl -sk -u '${var.bigip_admin_user}:${var.bigip_admin_password}' \
        https://${aws_eip.mgmt_eip[0].public_ip}/mgmt/tm/cm/device-group/failoverGroup/stats \
        > bigip1_sync_status.json

      cat bigip1_sync_status.json

      echo "Config sync triggered and status saved!"
    EOT
  }
}

# ── Validate DO on both BIG-IPs and save for outputs ─────────────────────────
resource "null_resource" "validate_do_config" {
  depends_on = [null_resource.trigger_config_sync]

  provisioner "local-exec" {
    command = <<-EOT
      CREDS1="${var.bigip_admin_user}:${var.bigip_admin_password}"
      IP1="${aws_eip.mgmt_eip[0].public_ip}"
      IP2="${aws_eip.mgmt_eip[1].public_ip}"

      echo "============================================"
      echo "Validating BIG-IP 1 Configuration..."
      echo "============================================"

      # DO info
      curl -sk -u "$CREDS1" \
        https://$IP1/mgmt/shared/declarative-onboarding/info \
        > bigip1_do_info.json
      echo "BIG-IP 1 DO Info:"
      cat bigip1_do_info.json

      # Self IPs
      curl -sk -u "$CREDS1" \
        https://$IP1/mgmt/tm/net/self \
        > bigip1_selfips.json
      echo "BIG-IP 1 Self IPs:"
      cat bigip1_selfips.json

      # VLANs
      curl -sk -u "$CREDS1" \
        https://$IP1/mgmt/tm/net/vlan \
        > bigip1_vlans.json

      # Device Group
      curl -sk -u "$CREDS1" \
        https://$IP1/mgmt/tm/cm/device-group \
        > bigip1_device_group.json
      echo "BIG-IP 1 Device Group:"
      cat bigip1_device_group.json

      # CM Devices (trust)
      curl -sk -u "$CREDS1" \
        https://$IP1/mgmt/tm/cm/device \
        > bigip1_cm_devices.json
      echo "BIG-IP 1 CM Devices:"
      cat bigip1_cm_devices.json

      echo "============================================"
      echo "Validating BIG-IP 2 Configuration..."
      echo "============================================"

      # DO info
      curl -sk -u "$CREDS1" \
        https://$IP2/mgmt/shared/declarative-onboarding/info \
        > bigip2_do_info.json
      echo "BIG-IP 2 DO Info:"
      cat bigip2_do_info.json

      # Self IPs
      curl -sk -u "$CREDS1" \
        https://$IP2/mgmt/tm/net/self \
        > bigip2_selfips.json
      echo "BIG-IP 2 Self IPs:"
      cat bigip2_selfips.json

      # VLANs
      curl -sk -u "$CREDS1" \
        https://$IP2/mgmt/tm/net/vlan \
        > bigip2_vlans.json

      # CM Devices
      curl -sk -u "$CREDS1" \
        https://$IP2/mgmt/tm/cm/device \
        > bigip2_cm_devices.json

      echo "All validation files saved!"
    EOT
  }
}