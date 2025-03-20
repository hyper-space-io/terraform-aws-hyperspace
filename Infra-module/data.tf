#######################
######## AWS ##########
#######################

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "tls_certificate" "tfc_certificate" {
  url = "https://${var.tfc_hostname}"
}

data "aws_region" "current" {}

#######################
### Terraform Cloud ###
#######################

data "tfe_organizations" "all" {}

data "tfe_workspace" "current" {
  name         = terraform.workspace
  organization = data.tfe_organizations.all.names[0]
}

#######################
######### EC2 #########
#######################

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_ami" "fpga" {
  owners     = ["337450623971"]
  name_regex = "eks-1\\.31-fpga-prod"
}

data "aws_iam_policy_document" "ec2_tags_control" {
  statement {
    sid = "EC2TagsAccess"
    actions = [
      "ec2:DescribeTags",
      "ec2:CreateTags"
    ]
    resources = [
      "arn:aws:ec2:*:*:instance/*"
    ]
    effect = "Allow"
  }
}

data "aws_iam_policy_document" "fpga_pull_access" {
  statement {
    sid = "PullAccessAGFI"
    actions = [
      "ec2:DeleteFpgaImage",
      "ec2:DescribeFpgaImages",
      "ec2:ModifyFpgaImageAttribute",
      "ec2:CreateFpgaImage",
      "ec2:DescribeFpgaImageAttribute",
      "ec2:CopyFpgaImage",
      "ec2:ResetFpgaImageAttribute",
      "kms:*"
    ]
    resources = [
      "arn:aws:ec2:${var.aws_region}::*",
      "arn:aws:kms:${var.aws_region}::*",
    ]
    effect = "Allow"
  }
}

#######################
######### EKS #########
#######################

data "aws_iam_policy_document" "cluster_autoscaler" {
  statement {
    sid = "AutoscalingWrite"
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup"
    ]
    resources = [
      "arn:aws:autoscaling:${var.aws_region}:${data.aws_caller_identity.current.account_id}:autoScalingGroup:*:autoScalingGroupName/*",
    ]
    effect = "Allow"
  }

  statement {
    sid = "AutoscalingRead"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeTags"
    ]
    resources = ["*"]
    effect    = "Allow"
  }

  statement {
    sid = "EC2Describe"
    actions = [
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:DescribeImages",
      "ec2:GetInstanceTypesFromInstanceRequirements"
    ]
    resources = ["*"]
    effect    = "Allow"
  }

  statement {
    sid = "EKSDescribe"
    actions = [
      "eks:DescribeNodegroup"
    ]
    resources = [
      "arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:nodegroup/${local.cluster_name}/*"
    ]
    effect = "Allow"
  }
}

#######################
######### S3 ##########
#######################
data "aws_iam_policy_document" "core_dump_s3_full_access" {
  statement {
    sid = "FullAccessS3CoreDump"
    actions = [
      "s3:*"
    ]
    resources = [
      "${module.s3_buckets["core-dump-logs"].s3_bucket_arn}",
      "${module.s3_buckets["core-dump-logs"].s3_bucket_arn}/*"
    ]
    effect = "Allow"
  }
}

data "aws_iam_policy_document" "velero_s3_full_access" {
  statement {
    sid = "FullAccessS3CoreDump"
    actions = [
      "s3:*"
    ]
    resources = [
      "${module.s3_buckets["velero"].s3_bucket_arn}",
      "${module.s3_buckets["velero"].s3_bucket_arn}/*"
    ]
    effect = "Allow"
  }
}

#######################
####### Loki ##########
#######################
data "aws_iam_policy_document" "loki_s3_dynamodb_full_access" {
  statement {
    actions = [
      "s3:ListBucket",
      "s3:PutObject",
      "s3:GetObject"
    ]
    effect = "Allow"
    resources = [
      "${module.s3_buckets["loki"].s3_bucket_arn}",
      "${module.s3_buckets["loki"].s3_bucket_arn}/*"
    ]
  }
  statement {
    actions = [
      "dynamodb:BatchGetItem",
      "dynamodb:BatchWriteItem",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable",
      "dynamodb:GetItem",
      "dynamodb:ListTagsOfResource",
      "dynamodb:PutItem",
      "dynamodb:Query",
      "dynamodb:TagResource",
      "dynamodb:UntagResource",
      "dynamodb:UpdateItem",
      "dynamodb:UpdateTable",
      "dynamodb:CreateTable",
      "dynamodb:DeleteTable"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.cluster_name}-loki-index-*"
    ]
  }
  statement {
    actions = [
      "dynamodb:ListTables"
    ]
    effect    = "Allow"
    resources = ["*"]
  }
  statement {
    actions = [
      "application-autoscaling:DescribeScalableTargets",
      "application-autoscaling:DescribeScalingPolicies",
      "application-autoscaling:RegisterScalableTarget",
      "application-autoscaling:DeregisterScalableTarget",
      "application-autoscaling:PutScalingPolicy",
      "application-autoscaling:DeleteScalingPolicy"
    ]
    effect    = "Allow"
    resources = ["*"]
  }
  statement {
    actions = [
      "iam:GetRole",
      "iam:PassRole"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.cluster_name}-loki"
    ]
  }
}

#######################
## Secrets Manager ####
#######################
data "aws_iam_policy_document" "secrets_manager" {
  statement {
    sid = "secretsmanager"
    actions = [
      "secretsmanager:GetResourcePolicy",
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecretVersionIds"
    ]
    resources = [
      "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:*",
    ]
    effect = "Allow"
  }
}

data "aws_iam_policy_document" "kms" {
  statement {
    sid    = "EnableIAMUserPermissions"
    effect = "Allow"

    actions = [
      "kms:Create*",
      "kms:Describe*",
      "kms:Enable*",
      "kms:List*",
      "kms:Put*",
      "kms:Update*",
      "kms:Revoke*",
      "kms:Disable*",
      "kms:Get*",
      "kms:Delete*",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowUseOfTheKey"
    effect = "Allow"

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowAttachmentOfPersistentResources"
    effect = "Allow"

    actions = [
      "kms:CreateGrant",
      "kms:ListGrants",
      "kms:RevokeGrant"
    ]

    resources = ["*"]

    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }
}