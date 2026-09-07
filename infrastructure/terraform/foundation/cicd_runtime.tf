# ── Phase 25 — extend the CI/CD deploy role for SSM-based deployment ─────────
# The live targets (staging/production) are single-instance Compose stacks with
# NO shell port (shell is SSM). GitHub Actions drives deploy/migrate/rollback/
# verify through SSM Run Command, so the ci-deploy role additionally needs:
#   ssm:SendCommand / GetInvocation   run deploy_backend.sh on the host
#   ec2 Describe*                     find the instance by Name tag
#   s3 Put/Get (optional)             long-run command output capture
data "aws_iam_policy_document" "ci_deploy_runtime" {
  statement {
    sid       = "SSMRunCommand"
    effect    = "Allow"
    actions = [
      "ssm:SendCommand",
      "ssm:GetCommandInvocation",
      "ssm:ListCommands",
      "ssm:ListCommandInvocations",
      "ssm:DescribeInstanceInformation",
    ]
    # SendCommand targets instances; it cannot be resource-scoped. The CI
    # trust policy restricts who may assume this role at all.
    resources = ["*"]
  }

  statement {
    sid       = "FindAppInstances"
    effect    = "Allow"
    actions   = ["ec2:DescribeInstances", "ec2:DescribeInstanceStatus", "ec2:DescribeTags"]
    resources = ["*"] # describe actions are not resource-scopable
  }

  statement {
    sid       = "SSMOutputToBackups"
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:GetObject"]
    resources = var.ssm_output_bucket != ""
      ? ["arn:aws:s3:::${var.ssm_output_bucket}", "arn:aws:s3:::${var.ssm_output_bucket}/*"]
      : []
  }
}

resource "aws_iam_role_policy" "ci_deploy_runtime" {
  count  = var.enable_ssm_deploy ? 1 : 0
  name   = "${var.project_name}-cicd-deploy-runtime"
  role   = aws_iam_role.ci_deploy.id
  policy = data.aws_iam_policy_document.ci_deploy_runtime.json
}