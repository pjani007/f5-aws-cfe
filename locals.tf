locals {
  cfe_declaration = {
    class       = "Cloud_Failover"
    environment = "aws"
    externalStorage = {
      scopingTags = {
        f5_cloud_failover_label = var.cfe_label
      }
    }
    failoverAddresses = {
      enabled = true
      scopingTags = {
        f5_cloud_failover_label = var.cfe_label
      }
    }
    failoverRoutes = {
      enabled = true
      scopingTags = {
        f5_cloud_failover_label = var.cfe_label
      }
      scopingAddressRanges = [
        for cidr in var.vip_subnet_ranges : { range = cidr }
      ]
      defaultNextHopAddresses = {
        discoveryType = "static"
        items         = var.bigip_external_self_ips
      }
    }
    controls = {
      class    = "Controls"
      logLevel = "info"
    }
  }
}