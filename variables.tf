variable "aws_region" { 
    type = string
}

variable "aws_account_id" {
    type = string
}

variable "vpc_id" { 
    type = string 
}

variable "vpc_cidr" { 
    type = string 
}

# Subnets
variable "mgmt_subnet_ids" { 
    type = list(string) 
}

variable "ext_subnet_ids" { 
    type = list(string) 
}

variable "int_subnet_ids" { 
    type = list(string) 
}

variable "internal_subnet_ids" { 
    type = list(string) 
}

# EC2 & BIG-IP Params
variable "f5_ami_id" { 
    type = string 
}

variable "instance_type" { 
    type = string 
    default = "m5.xlarge" 
}

variable "key_name" { 
    type = string 
}

variable "license_keys" { 
    type = list(string) 
}

variable "cfe_url" { 
    type = string 
    default = "https://github.com/F5Networks/f5-cloud-failover-extension/releases/download/v2.2.0/f5-cloud-failover-2.2.0-0.noarch.rpm" 
}

# Security Group Allowed IPs

variable "mgmt_allow_ips" { 
    type = list(string) 
}

variable "ext_allow_ips" { 
    type = list(string) 
    default = ["0.0.0.0/0"] 
}

# CFE Specific

variable "route_table_ids" { 
    type = list(string) 
}

variable "cfe_label" { 
    type    = string
    default = "cfe-failover-active-standby"
}

variable "vip_subnet_ranges" { 
    type = list(string) 
}

variable "bigip_external_self_ips" { 
    type = list(string) 
}

variable "bigip1_mgmt_ip" { 
    type = string 
}

variable "bigip2_mgmt_ip" { 
    type = string 
}

variable "bigip_admin_user" { 
    type = string 
    default = "admin"
}

variable "bigip_admin_password" { 
    type = string 
    sensitive = true 
}

variable "do_url" { 
    type    = string
    default = "https://github.com/F5Networks/f5-declarative-onboarding/releases/download/v1.47.0/f5-declarative-onboarding-1.47.0-14.noarch.rpm" 
}

variable "bigip_internal_self_ips" { 
    type        = list(string)
    description = "Primary private IPs for the Internal ENIs (e.g., ['10.0.3.100', '10.0.3.101'])"
}
variable "bigip_int_gws" {
  type        = list(string)
  description = "Internal subnet gateways for each BIG-IP (AWS .1 address of each internal subnet)"
}