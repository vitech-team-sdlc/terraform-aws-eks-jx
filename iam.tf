
resource "aws_iam_group" "developers" {
  name = "${var.cluster_name}-developers"
}

resource "aws_iam_group" "admins" {
  name = "${var.cluster_name}-admins"
}

resource "aws_iam_policy" "dev_policy" {
  name        = "${var.cluster_name}-IAMUpdateOwnCreds"
  description = "Custom: User has ability to update own credentials"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "iam:UpdateLoginProfile",
          "iam:DeactivateMFADevice",
          "iam:DeleteAccessKey",
          "iam:EnableMFADevice",
          "iam:ResyncMFADevice",
          "iam:UpdateAccessKey",
          "iam:CreateVirtualMFADevice",
          "iam:DeleteLoginProfile",
          "iam:ChangePassword",
          "iam:CreateAccessKey"
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:iam::*:mfa/*",
          "arn:aws:iam::*:user/$${aws:username}"
        ]
      },
    ]
  })
}

data "aws_iam_policy" "read_only_access" {
  name = "ReadOnlyAccess"
}

data "aws_iam_policy" "admin_access" {
  name = "AdministratorAccess"
}

resource "aws_iam_group_policy_attachment" "dev_read_only" {
  group      = aws_iam_group.developers.name
  policy_arn = data.aws_iam_policy.read_only_access.arn
}

resource "aws_iam_group_policy_attachment" "dev_update_creds" {
  group      = aws_iam_group.developers.name
  policy_arn = aws_iam_policy.dev_policy.arn
}

resource "aws_iam_group_policy_attachment" "admin_access" {
  group      = aws_iam_group.admins.name
  policy_arn = data.aws_iam_policy.admin_access.arn
}

#
# added mapRoles to aws-auth ConfigMap
# - rolearn: arn:aws:iam::684654654652:role/cluster--AWS-EKS-ReadOnly-Role
# username: read-only-user
# groups:
# - read-only-users
# - rolearn: arn:aws:iam::684654654652:role/cluster--AWS-EKS-Admin-Role
# username: admin-user
# groups:
#- system:masters
#
# Add user to "cluster-admins" group and to "cluster-EKS-Admin"
# aws eks update-kubeconfig --name cluster --role-arn arn:aws:iam::684654654652:role/cluster--AWS-EKS-Admin-Role --profile test-aws-profile --region=us-east-1
#     or
# Add user to "cluster-developers" group and to "cluster-EKS-ReadOnly" group
# aws eks update-kubeconfig --name cluster --role-arn arn:aws:iam::684654654652:role/cluster--AWS-EKS-ReadOnly-Role --profile test-aws-profile --region=us-east-1
#
# Remove groups from user assigned manually before destroy
#

locals {
  roles = toset(["Admin", "ReadOnly"])
  mapRoles = [{
      rolearn  = aws_iam_role.eks_role["ReadOnly"].arn
      username = "read-only-user"
      groups   = ["read-only-user"]
    }, {
      rolearn  = aws_iam_role.eks_role["Admin"].arn
      username = "admin-user"
      groups   = ["system:masters"]
  }]
}

resource "aws_iam_role" "eks_role" {
  for_each = local.roles
  name     = "${var.cluster_name}--AWS-EKS-${each.key}-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        "Effect" = "Allow",
        "Principal" = {
          "AWS" = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        "Action"    = "sts:AssumeRole",
        "Condition" = {}
      }
    ]
  })
}

resource "aws_iam_policy" "eks_policy" {
  for_each    = local.roles
  name        = "${var.cluster_name}--AWS-EKS-Assume-${each.key}-Role-Policy"
  path        = "/"
  description = "Policy that allows users in appropriate group to assume ${each.key} role for eks"

  policy = jsonencode({
    "Version" = "2012-10-17",
    "Statement" = [
      {
        "Sid"      = "VisualEditor0",
        "Effect"   = "Allow",
        "Action"   = "eks:ListClusters",
        "Resource" = "*"
      },
      {
        "Sid"    = "VisualEditor1",
        "Effect" = "Allow",
        "Action" = [
          "sts:AssumeRole",
          "eks:DescribeCluster"
        ],
        "Resource" = [
          "arn:aws:eks:us-east-1:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}",
          "${aws_iam_role.eks_role[each.key].arn}"
        ]
      }
    ]
  })
}

resource "aws_iam_group" "eks_group" {
  for_each = local.roles
  name     = "${var.cluster_name}-EKS-${each.key}"
}

resource "aws_iam_group_policy_attachment" "eks_group_attach" {
  for_each   = local.roles
  group      = aws_iam_group.eks_group[each.key].name
  policy_arn = aws_iam_policy.eks_policy[each.key].arn
}
