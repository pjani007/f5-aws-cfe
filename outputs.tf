output "cfe_s3_bucket_name" {
  value = aws_s3_bucket.cfe_state_bucket.bucket
}

output "bigip_iam_instance_profile" {
  value = aws_iam_instance_profile.bigip_profile.name
}

output "ec2_endpoint_dns" {
  value = aws_vpc_endpoint.ec2.dns_entry[0].dns_name
}

output "bigip_mgmt_ips" {
  value       = aws_eip.mgmt_eip[*].public_ip # <-- Updated to pull strictly from the EIP resource
  description = "Public Management IPs for the BIG-IPs"
}

output "bigip_instance_ids" {
  value = aws_instance.bigip[*].id
}
output "bigip1_do_verification" {
  description = "JSON verification output of DO installation on BIG-IP 1"
  value       = try(jsondecode(file("${path.module}/bigip1_do_info.json")), "Awaiting Terraform Apply to generate JSON...")
}

output "bigip1_cfe_verification" {
  description = "JSON verification output of CFE installation on BIG-IP 1"
  value       = try(jsondecode(file("${path.module}/bigip1_cfe_info.json")), "Awaiting Terraform Apply to generate JSON...")
}

output "bigip2_do_verification" {
  description = "JSON verification output of DO installation on BIG-IP 2"
  value       = try(jsondecode(file("${path.module}/bigip2_do_info.json")), "Awaiting Terraform Apply to generate JSON...")
}

output "bigip2_cfe_verification" {
  description = "JSON verification output of CFE installation on BIG-IP 2"
  value       = try(jsondecode(file("${path.module}/bigip2_cfe_info.json")), "Awaiting Terraform Apply to generate JSON...")
}