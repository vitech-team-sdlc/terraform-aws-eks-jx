
resource "aws_iam_group" "developers" {
  name = "developers"
}

resource "aws_iam_group" "admins" {
  name = "admins"
}

resource "aws_iam_policy" "dev_policy" {
  name        = "IAMUpdateOwnCreds"
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
        Effect   = "Allow"
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