resource "aws_iam_role" "bigip_cfe_role" {
  name = "bigip-cfe-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_policy" "bigip_cfe_policy" {
  name = "bigip-cfe-strict-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListAllMyBuckets"]
        Resource = "*"
        Condition = { StringEquals = { "aws:PrincipalAccount" = var.aws_account_id } }
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation", "s3:GetBucketTagging"]
        Resource = aws_s3_bucket.cfe_state_bucket.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.cfe_state_bucket.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = [
          "ec2:DescribeAddresses", "ec2:DescribeInstances", "ec2:DescribeInstanceStatus",
          "ec2:DescribeNetworkInterfaces", "ec2:DescribeNetworkInterfaceAttribute",
          "ec2:DescribeSubnets", "ec2:DescribeRouteTables"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion"  = var.aws_region,
            "aws:PrincipalAccount" = var.aws_account_id
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = [
          "ec2:AssociateAddress", "ec2:DisassociateAddress",
          "ec2:AssignPrivateIpAddresses", "ec2:UnassignPrivateIpAddresses"
        ]
        Resource = concat(
          formatlist("arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:elastic-ip/%s", aws_eip.mgmt_eip[*].id),
          formatlist("arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:network-interface/%s", aws_network_interface.external[*].id),
          formatlist("arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:instance/%s", aws_instance.bigip[*].id)
        )
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateRoute", "ec2:ReplaceRoute"]
        Resource = formatlist("arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:route-table/%s", var.route_table_ids)
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cfe_attach" {
  role       = aws_iam_role.bigip_cfe_role.name
  policy_arn = aws_iam_policy.bigip_cfe_policy.arn
}

resource "aws_iam_instance_profile" "bigip_profile" {
  name = "bigip-cfe-profile"
  role = aws_iam_role.bigip_cfe_role.name
}