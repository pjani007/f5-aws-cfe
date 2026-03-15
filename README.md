# F5 BIG-IP Cloud Failover Extension (CFE) — AWS Private Endpoint Deployment

> **Active/Standby BIG-IP HA on AWS with fully private, air-gapped failover via VPC Interface & Gateway Endpoints**

---

## Table of Contents

1. [What is the F5 Cloud Failover Extension?](#1-what-is-the-f5-cloud-failover-extension)
2. [CFE vs AWS ALB — Why CFE Wins](#2-cfe-vs-aws-alb--why-cfe-wins)
3. [Architecture Overview](#3-architecture-overview)
4. [Why Private Endpoints?](#4-why-private-endpoints)
5. [Route Table Behaviour During Failover](#5-route-table-behaviour-during-failover)
6. [Prerequisites](#6-prerequisites)
7. [Step-by-Step Deployment Guide](#7-step-by-step-deployment-guide)
8. [Testing CFE Failover](#8-testing-cfe-failover)
9. [Expected Outputs](#9-expected-outputs)
10. [Troubleshooting](#10-troubleshooting)
11. [License](#11-license)

---

## 1. What is the F5 Cloud Failover Extension?

The **Cloud Failover Extension (CFE)** is an iControl LX REST API plugin installed on F5 BIG-IP instances running in public cloud environments. It solves a fundamental problem: **cloud hypervisors do not support Layer 2 protocols**.

In a traditional on-premises data centre, when an Active BIG-IP fails, the Standby device sends a **Gratuitous ARP (GARP)** broadcast to announce that it now owns the Virtual IP (VIP) addresses. Every network device on the segment updates its ARP cache within milliseconds, and traffic flows to the new device — all without touching the cloud control plane.

**This does not work in AWS.** AWS VPCs suppress GARP. The cloud has no Layer 2 broadcast domain. Without CFE, a failover event would leave the VIP addresses stranded on a dead instance with no mechanism to move them.

CFE replaces GARP with **programmatic AWS API calls**. When the Standby promotes itself, CFE calls the AWS EC2 API to:

- **Reassign secondary private IP addresses** (VIPs) from the failed instance's Elastic Network Interface (ENI) to the new Active instance's ENI.
- **Update AWS Route Tables** to point next-hop routing entries to the new Active instance's internal ENI.

The result is functionally identical to an on-premises GARP failover — traffic follows the Active node — but it is achieved through cloud-native API automation rather than Layer 2 broadcasting.

**CFE components on the BIG-IP:**

| Component | Role |
|---|---|
| `restnoded` daemon | Hosts the iControl LX plugin runtime |
| CFE RPM package | The failover logic, API call payload, and state engine |
| `failover.json` | Configuration file declaring which IPs, route tables, and S3 bucket CFE manages |
| S3 state bucket | Shared storage used by both BIG-IPs to track the current Active node and VIP ownership |

---

## 2. CFE vs AWS ALB — Why CFE Wins

A common architectural question is: *"Why not just put an AWS Application Load Balancer (ALB) in front of the BIG-IPs and let AWS handle availability?"*

The ALB is a valid choice for simple HTTP/HTTPS Layer 7 load balancing of web applications. But the moment enterprise networking, security, and application delivery requirements enter the picture, the ALB's limitations become blockers.

| Capability | F5 BIG-IP + CFE | AWS ALB |
|---|---|---|
| **IP address mobility** | VIPs follow the Active node; clients connect to a fixed IP address | ALB uses a DNS name; clients must tolerate DNS TTL delays during scaling/failover |
| **Route table control** | CFE directly updates AWS routing to steer return traffic (asymmetric routing fix) | No route table management |
| **Failover RTO** | Typically 10–30 seconds (heartbeat detection + CFE API execution) | Multi-AZ failover handled by AWS; no BIG-IP-level HA |
| **Network segmentation** | BIG-IP bridges external, DMZ, and internal segments; traffic never bypasses the device | ALB operates within a single VPC tier |

**The fundamental difference:** An ALB is a **cloud-managed shared service** that AWS scales behind a DNS name. A BIG-IP pair with CFE is a **dedicated traffic proxy** you control entirely — the IP addresses are yours, the policy is yours, and failover is a deterministic API event you can observe and test.

For environments requiring Layer 4/7 security, protocol flexibility, regulatory compliance, or integration with existing F5 tooling, CFE is not just preferable — it is the only viable path.

---

## 3. Architecture Overview

```
                          ┌─────────────────────────────────────────────┐
                          │                  AWS VPC                    │
                          │                                             │
   Internet / Users       │   External Subnet (AZ-1 / AZ-2)            │
   ──────────────►  EIP ──►  [ENI-EXT-1]          [ENI-EXT-2]          │
                          │   BIG-IP-1 (Active)   BIG-IP-2 (Standby)   │
                          │   [ENI-MGMT-1]        [ENI-MGMT-2]         │
                          │   [ENI-INT-1]         [ENI-INT-2]          │
                          │        │                    │               │
                          │   Internal Subnet (AZ-1 / AZ-2)            │
                          │        │                                    │
                          │   ┌────▼──────────────────────────────┐    │
                          │   │      Backend Application Tier      │    │
                          │   └───────────────────────────────────┘    │
                          │                                             │
                          │   ┌─────────────────┐  ┌────────────────┐  │
                          │   │  S3 Gateway EP   │  │ EC2 Interface  │  │
                          │   │  (CFE state)     │  │ EP (API calls) │  │
                          │   └─────────────────┘  └────────────────┘  │
                          │                                             │
                          └─────────────────────────────────────────────┘
```

**HA Heartbeat:** BIG-IP-1 and BIG-IP-2 exchange HA heartbeats over their Management or Internal ENIs. Detection of a missed heartbeat triggers the Standby to initiate promotion.

**CFE State Bucket:** Both BIG-IPs read from and write to a shared S3 bucket. This is how the newly promoted Active node knows which VIPs and Route Table entries it needs to claim.

**Private Endpoint routing:** All CFE API calls to `ec2.amazonaws.com` and `s3.amazonaws.com` resolve to private IP addresses inside the VPC and are routed over the AWS backbone — never the internet.

---

## 4. Why Private Endpoints?

By default, BIG-IP CFE must reach the public AWS API endpoints to execute a failover. This traditionally required either an Internet Gateway with NAT, or a NAT Gateway — both of which introduce cost, complexity, and single points of failure into the critical failover path.

This deployment provisions two private connectivity constructs:

### S3 Gateway Endpoint

A **Gateway Endpoint** is a free, highly available VPC routing construct. It adds a prefix list entry to your route tables that directs all S3-bound traffic into the AWS private network, bypassing the IGW entirely. CFE uses S3 to read and write failover state.

### EC2 Interface Endpoint (PrivateLink)

An **Interface Endpoint** provisions an ENI inside your subnet with a private IP address. AWS creates a private DNS record for `ec2.<region>.amazonaws.com` that resolves to this ENI. When CFE calls the EC2 API to reassign VIPs and update route tables, the DNS resolution returns a private IP — the call travels over PrivateLink, never the internet.

### Benefits Summary

| Benefit | Detail |
|---|---|
| **Security** | Failover API calls are never exposed to the internet. No data traverses a public endpoint. |
| **Reliability** | Removes the Internet Gateway and NAT Gateway from the failover critical path. Fewer components = fewer failure modes. |
| **Compliance** | Satisfies air-gapped and network-isolated architecture requirements (PCI-DSS, FedRAMP, HIPAA). |
| **Visibility** | VPC Flow Logs capture all traffic to and from the Interface Endpoint ENI for forensic review. |

---

## 5. Route Table Behaviour During Failover

Understanding how CFE manipulates AWS Route Tables is essential for designing your network correctly and for verifying that failover succeeded.

### Pre-Failover State (Normal Operation)

Your internal route tables contain a static entry directing application return traffic to the Active BIG-IP's internal ENI:

```
Route Table: rtb-0abc123 (Internal/Private tier)
Destination        Target
0.0.0.0/0          eni-0xxxxxxxxxxx  (BIG-IP-1 Internal ENI — Active)
10.0.0.0/8         local
```

### During Failover

When BIG-IP-2 (previously Standby) detects BIG-IP-1 is down and promotes itself to Active, CFE performs the following atomic operations via the EC2 API:

1. **IP Reassignment:** CFE calls `AssignPrivateIpAddresses` to move the secondary VIP addresses from BIG-IP-1's External ENI (`eni-0xxxxxxxxxxx`) to BIG-IP-2's External ENI.

2. **Route Table Update:** CFE calls `ReplaceRoute` to update every tagged Route Table entry. The `0.0.0.0/0` (or your specific application CIDR) next-hop target is replaced:

```
Route Table: rtb-0abc123 (Internal/Private tier) — POST FAILOVER
Destination        Target
0.0.0.0/0          eni-0yyyyyyyyyyy  (BIG-IP-2 Internal ENI — now Active)
10.0.0.0/8         local
```

3. **S3 State Write:** CFE writes the new Active node's identity back to the S3 state bucket so both devices have a consistent view of ownership.

### CFE Route Table Tagging

CFE identifies which route tables to update via AWS resource tags. This Terraform deployment tags the relevant route tables during provisioning:

```hcl
tags = {
  "f5_cloud_failover_label" = "cfe-deployment"
}
```

CFE reads this tag value from its configuration (`failover.json`) and only manipulates route tables bearing this exact label. This scoping prevents CFE from accidentally modifying unrelated route tables in the same VPC.

> **Design note:** Ensure that your application return-traffic route tables are tagged, but your Management subnet route tables are **not** — management connectivity must remain stable during a failover event so you can observe and troubleshoot the newly Active device.

---

## 6. Prerequisites

### 6.1 Network Infrastructure

| Resource | Description | Example |
|---|---|---|
| VPC ID | The VPC where BIG-IPs will be deployed | `vpc-0a1b2c3d4e5f` |
| Management Subnets (×2) | One per AZ; must be public with IGW route if GUI access is required | `subnet-mgmt-az1`, `subnet-mgmt-az2` |
| External Subnets (×2) | One per AZ; receives internet-facing traffic via EIP | `subnet-ext-az1`, `subnet-ext-az2` |
| Internal Subnets (×2) | One per AZ; connects to application backend | `subnet-int-az1`, `subnet-int-az2` |
| Route Table IDs | Private route tables CFE will update during failover | `rtb-0abc123456` |

### 6.2 Compute & Licensing

| Resource | Description | Example |
|---|---|---|
| F5 BIG-IP AMI ID | Region-specific AMI for your desired BIG-IP version (BYOL) | `ami-0abcdef1234567890` |
| EC2 Key Pair | Existing AWS key pair for SSH access | `my-bigip-keypair` |
| BIG-IP License Keys | Two valid F5 Base Registration Keys (one per device) | `XXXXX-XXXXX-XXXXX-XXXXX` |
| Instance Type | Recommended: `m5.2xlarge` or larger for production workloads | `m5.2xlarge` |

### 6.3 IAM Permissions

The IAM role attached to the BIG-IP EC2 instances must include the following permissions:

```json
{
  "Effect": "Allow",
  "Action": [
    "ec2:AssignPrivateIpAddresses",
    "ec2:UnassignPrivateIpAddresses",
    "ec2:DescribeInstances",
    "ec2:DescribeNetworkInterfaces",
    "ec2:DescribeRouteTables",
    "ec2:ReplaceRoute",
    "s3:GetObject",
    "s3:PutObject",
    "s3:ListBucket"
  ],
  "Resource": "*"
}
```

### 6.4 Tooling

| Tool | Minimum Version | Purpose |
|---|---|---|
| Terraform | `>= 1.3.0` | Infrastructure provisioning |
| AWS CLI | `>= 2.x` | Authentication and manual verification |
| curl / jq | Any | Manual CFE API interaction during testing |

---

## 7. Step-by-Step Deployment Guide

### Step 1 — Clone the Repository

```bash
git clone <your-repository-url>
cd awscfe
```

### Step 2 — Configure Remote State (Strongly Recommended)

Local state files are lost if the runner is destroyed and cannot support team collaboration. Update `providers.tf` with your S3 backend:

```hcl
terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "f5-cfe/terraform.tfstate"
    region         = "eu-west-1"
    encrypt        = true
    dynamodb_table = "terraform-state-locks"
  }
}
```

Create the DynamoDB table for state locking if it does not already exist:

```bash
aws dynamodb create-table \
  --table-name terraform-state-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region eu-west-1
```

### Step 3 — Populate Variables

Create a `terraform.tfvars` file in the root directory. Refer to `variables.tf` for the full schema. A representative configuration:

```hcl
# --- Networking ---
aws_region         = "eu-west-1"
vpc_id             = "vpc-0a1b2c3d4e5f"
mgmt_subnet_ids    = ["subnet-mgmt-az1", "subnet-mgmt-az2"]
external_subnet_ids = ["subnet-ext-az1", "subnet-ext-az2"]
internal_subnet_ids = ["subnet-int-az1", "subnet-int-az2"]
route_table_ids    = ["rtb-0abc123456"]

# --- Compute ---
bigip_ami_id       = "ami-0abcdef1234567890"
instance_type      = "m5.2xlarge"
key_pair_name      = "my-bigip-keypair"

# --- Licensing ---
bigip1_license_key = "AAAAA-BBBBB-CCCCC-DDDDD"
bigip2_license_key = "EEEEE-FFFFF-GGGGG-HHHHH"

# --- CFE ---
cfe_label          = "cfe-deployment"
cfe_s3_bucket      = "my-bigip-cfe-state-bucket"
```

Set the BIG-IP admin password via an environment variable to avoid committing credentials:

```bash
export TF_VAR_bigip_admin_password="YourSecurePassword123!"
```

> **Security note:** Add `terraform.tfvars` to `.gitignore`. Never commit license keys or passwords to source control.

### Step 4 — Initialise Terraform

Download required providers and initialise the configured backend:

```bash
terraform init
```

Expected output:

```
Initialising the backend...
Successfully configured the backend "s3"!

Initialising provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.x.x...
- Installed hashicorp/aws v5.x.x (signed by HashiCorp)

Terraform has been successfully initialised!
```

### Step 5 — Review the Plan

Inspect all resources before deployment. Pay particular attention to Security Group rules, ENI configurations, and route table tags:

```bash
terraform plan -out=tfplan
```

Verify the plan includes:
- `aws_vpc_endpoint` for both S3 (gateway) and EC2 (interface)
- `aws_instance` × 2 (both BIG-IP nodes)
- `aws_iam_role` and `aws_iam_instance_profile` for CFE permissions
- `aws_s3_bucket` for CFE state
- `aws_network_interface` for each ENI tier (management, external, internal) per node

### Step 6 — Apply the Configuration

```bash
terraform apply tfplan
```

> Type `yes` when prompted if you run without a saved plan.

**What happens during apply (in sequence):**

1. VPC Endpoints (S3 Gateway + EC2 Interface) are created first — CFE depends on them.
2. IAM roles and instance profiles are provisioned.
3. S3 state bucket is created and tagged.
4. ENIs are created and attached to the correct subnets.
5. Security Groups are applied.
6. EC2 instances launch and the BIG-IP `MCPD` service initialises (~5–8 minutes).
7. Terraform waits for the REST API to become available, then sets the admin password.
8. License keys are activated via the F5 licensing API.
9. The CFE RPM is downloaded and installed on both instances.
10. The `failover.json` configuration is pushed to both BIG-IPs via the CFE REST API.

Total apply time: **15–25 minutes** depending on AWS region and licensing server response time.

### Step 7 — Verify Endpoint Outputs

After a successful apply, Terraform outputs the relevant IP addresses:

```bash
terraform output
```

Example output:

```
bigip1_management_public_ip  = "52.x.x.x"
bigip2_management_public_ip  = "54.x.x.x"
bigip1_management_private_ip = "10.0.1.10"
bigip2_management_private_ip = "10.0.1.11"
cfe_s3_bucket_name           = "my-bigip-cfe-state-bucket"
ec2_endpoint_dns             = "vpce-xxxx.ec2.eu-west-1.vpce.amazonaws.com"
```

---

## 8. Testing CFE Failover

### 8.1 Pre-Test Checks

Before forcing a failover, confirm both devices are healthy and CFE is configured correctly.

**Check HA sync state on BIG-IP-1:**

```bash
ssh -i /path/to/key.pem admin@<bigip1-mgmt-ip>
tmsh show cm sync-status
```

Expected:

```
--------------------------------------------
| Sync Status                              |
--------------------------------------------
  Color       green
  Status      In Sync
```

**Verify CFE configuration via REST API:**

```bash
curl -sku admin:${BIGIP_PASS} \
  https://<bigip1-mgmt-ip>/mgmt/shared/cloud-failover/declare \
  | python3 -m json.tool
```

Confirm that `failoverAddresses`, `failoverRoutes`, and the S3 bucket name are all present and correct in the response.

**Record the current AWS Route Table state before failover:**

```bash
aws ec2 describe-route-tables \
  --route-table-ids rtb-0abc123456 \
  --query 'RouteTables[*].Routes' \
  --region eu-west-1
```

Note the current ENI ID in the `NetworkInterfaceId` field — you will verify it changes after failover.

### 8.2 Open a Live Log Stream

SSH to BIG-IP-1 (the current Active) and tail the CFE log:

```bash
ssh -i /path/to/key.pem admin@<bigip1-mgmt-ip>
tail -f /var/log/restnoded/restnoded.log
```

Leave this terminal open. The CFE state transition events will stream here during the test.

### 8.3 Force Failover via BIG-IP GUI

1. Navigate to `https://<bigip1-mgmt-ip>` and log in as `admin`.
2. Go to **Device Management → Devices**.
3. Click the local device (labelled `(Self)`).
4. Click **Force to Standby**.
5. Confirm the action in the dialog.

Alternatively, force failover via the CLI on BIG-IP-1:

```bash
tmsh run sys failover standby
```

### 8.4 Force Failover via CFE REST API (Recommended for Automation)

```bash
curl -sku admin:${BIGIP_PASS} \
  -X POST \
  https://<bigip1-mgmt-ip>/mgmt/shared/cloud-failover/trigger \
  -H 'Content-Type: application/json' \
  -d '{"action":"failover"}'
```

---

## 9. Expected Outputs

### 9.1 CFE Log Output — restnoded.log

Immediately after triggering failover, you will see the following sequence on BIG-IP-2's log (`/var/log/restnoded/restnoded.log`):

```
[CloudFailoverExtension] [INFO] Failover started
[CloudFailoverExtension] [INFO] Device state change detected: standby -> active
[CloudFailoverExtension] [INFO] Getting failover state from S3 bucket: my-bigip-cfe-state-bucket
[CloudFailoverExtension] [INFO] Previous Active device: i-0aaaaaaaaaaaaaaa1 (BIG-IP-1)
[CloudFailoverExtension] [INFO] This device is: i-0bbbbbbbbbbbbbbb2 (BIG-IP-2)
[CloudFailoverExtension] [INFO] Starting IP address failover...
[CloudFailoverExtension] [INFO] Unassigning IP 10.0.2.100 from ENI eni-0xxxxxxxxxxx (BIG-IP-1 External)
[CloudFailoverExtension] [INFO] Assigning IP 10.0.2.100 to ENI eni-0yyyyyyyyyyy (BIG-IP-2 External)
[CloudFailoverExtension] [INFO] IP address failover complete.
[CloudFailoverExtension] [INFO] Starting route failover...
[CloudFailoverExtension] [INFO] Updating Route Table rtb-0abc123456: 0.0.0.0/0 -> eni-0yyyyyyyyyyy
[CloudFailoverExtension] [INFO] Route Table update complete.
[CloudFailoverExtension] [INFO] Writing new state to S3 bucket: my-bigip-cfe-state-bucket
[CloudFailoverExtension] [INFO] Failover complete. Elapsed time: 12.4s
```

### 9.2 BIG-IP GUI — Device Management

After failover, on BIG-IP-2's GUI under **Device Management → Devices**:

```
Device: bigip2.example.com  (Self)       Status: ACTIVE
Device: bigip1.example.com               Status: STANDBY
```

### 9.3 AWS Route Table Verification

Run the same describe command you used in the pre-test check:

```bash
aws ec2 describe-route-tables \
  --route-table-ids rtb-0abc123456 \
  --query 'RouteTables[*].Routes' \
  --region eu-west-1
```

Expected output (the `NetworkInterfaceId` now points to BIG-IP-2's Internal ENI):

```json
[
  [
    {
      "DestinationCidrBlock": "0.0.0.0/0",
      "NetworkInterfaceId": "eni-0yyyyyyyyyyy",
      "State": "active"
    },
    {
      "DestinationCidrBlock": "10.0.0.0/16",
      "GatewayId": "local",
      "State": "active"
    }
  ]
]
```

### 9.4 CFE State Check via REST API

After failover, query the CFE state endpoint on BIG-IP-2 to confirm its self-assessment:

```bash
curl -sku admin:${BIGIP_PASS} \
  https://<bigip2-mgmt-ip>/mgmt/shared/cloud-failover/inspect \
  | python3 -m json.tool
```

Expected:

```json
{
  "declaration": {
    "class": "CloudFailover",
    "environment": "aws"
  },
  "deviceStatus": "active",
  "failoverStatus": {
    "code": 200,
    "message": "Failover complete",
    "taskState": "SUCCEEDED"
  }
}
```

### 9.5 End-to-End Traffic Test

If you have a virtual server configured on the BIG-IPs, send a test request to confirm traffic is flowing through the new Active device:

```bash
curl -v http://<VIP-address>/
```

You should receive a valid application response with zero packet loss, confirming that CFE correctly moved the VIP and updated routing before your test client noticed the interruption.

---

## 10. Troubleshooting

| Symptom | Likely Cause | Resolution |
|---|---|---|
| CFE log shows `AccessDenied` on EC2 API call | IAM role missing required EC2 permissions | Verify the instance profile policy includes `ec2:ReplaceRoute` and `ec2:AssignPrivateIpAddresses` |
| CFE log shows `Could not reach ec2.amazonaws.com` | EC2 Interface Endpoint not reachable | Check security group on the Interface Endpoint allows inbound 443 from BIG-IP subnets; verify private DNS is enabled on the endpoint |
| Route table not updated after failover | Route table not tagged with CFE label | Add tag `f5_cloud_failover_label = "cfe-deployment"` to the target route table |
| S3 state read failure | S3 Gateway Endpoint not in route table | Confirm the S3 prefix list entry is present in the private subnet route table via `aws ec2 describe-route-tables` |
| Both devices show `STANDBY` after failover | HA group misconfiguration | Check HA heartbeat connectivity between internal ENIs; verify traffic group configuration on both devices |
| `terraform apply` times out waiting for MCPD | Instance launch too slow or wrong AMI | Increase the `create_timeout` variable; verify the AMI ID is correct for the target region |

---

## 11. License

This project is licensed under the **GNU General Public License v3.0**. See the `LICENSE` file for full terms.

---

*Maintained by your network automation team. Raise issues or PRs against this repository for fixes and enhancements.*