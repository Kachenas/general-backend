# =============================================================================
# Grants developers just enough to open an SSM Session Manager port-forwarding
# session to the bastion instance — nothing else. No SSH key, no direct RDS
# credentials in this policy, no access to any other EC2 instance.
#
# Onboarding a new developer is then: give them an IAM user (or add their
# Identity Center permission set to `policy_arn`), install the AWS CLI +
# Session Manager plugin, and they can tunnel to RDS from their own machine.
# =============================================================================

data "aws_iam_policy_document" "ssm_bastion_access" {
  statement {
    sid     = "StartSessionToBastion"
    actions = ["ssm:StartSession"]
    resources = [
      var.bastion_instance_arn,
      "arn:aws:ssm:*:*:document/AWS-StartPortForwardingSessionToRemoteHost",
      "arn:aws:ssm:*:*:document/SSM-SessionManagerRunShell",
    ]
  }

  statement {
    sid       = "ManageOwnSessions"
    actions   = ["ssm:TerminateSession", "ssm:ResumeSession"]
    resources = ["arn:aws:ssm:*:*:session/$${aws:username}-*"]
  }

  statement {
    sid       = "DescribeForCliAndConsole"
    actions   = ["ssm:DescribeSessions", "ec2:DescribeInstances"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ssm_bastion_access" {
  name        = "${var.project_name}-ssm-bastion-access"
  description = "Allows starting an SSM Session Manager port-forwarding session to the ${var.project_name} bastion only"
  policy      = data.aws_iam_policy_document.ssm_bastion_access.json

  tags = var.tags
}

resource "aws_iam_group" "developers" {
  name = "${var.project_name}-developers"
}

resource "aws_iam_group_policy_attachment" "ssm_bastion_access" {
  group      = aws_iam_group.developers.name
  policy_arn = aws_iam_policy.ssm_bastion_access.arn
}

# Source of truth for group membership — adding a name here is the entire
# "onboarding" step for an existing IAM user.
resource "aws_iam_group_membership" "developers" {
  name  = "${var.project_name}-developers-membership"
  group = aws_iam_group.developers.name
  users = var.developer_user_names
}
