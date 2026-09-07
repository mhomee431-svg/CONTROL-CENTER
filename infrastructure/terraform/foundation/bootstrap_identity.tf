# ── Bootstrap human identity + account hardening (MFA, no admin keys) ────────

# Bootstrap IAM user: capable of ONLY assuming the operator role. Its access
# keys are the *only* long-lived credential allowed in the whole design; they
# cannot touch AWS resources directly.
resource "aws_iam_user" "bootstrap" {
  name = "${var.project_name}-bootstrap"
  tags = { Name = "${var.project_name}-bootstrap", Purpose = "Assumes operator role only" }
}

data "aws_iam_policy_document" "bootstrap_only_operator" {
  statement {
    sid       = "AssumeOperatorRoleOnly"
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.operator.arn]
  }
}

resource "aws_iam_user_policy" "bootstrap" {
  name   = "${var.project_name}-bootstrap-assume-op"
  user   = aws_iam_user.bootstrap.name
  policy = data.aws_iam_policy_document.bootstrap_only_operator.json
}

resource "aws_iam_access_key" "bootstrap" {
  user = aws_iam_user.bootstrap.name
}

# ── Ops group for additional human admins (must also be in operator_principals)
resource "aws_iam_group" "ops" {
  name = "${var.project_name}-ops"
}

data "aws_iam_policy_document" "ops_assume_operator" {
  statement {
    sid       = "AssumeOperator"
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.operator.arn]
  }
}

resource "aws_iam_group_policy" "ops" {
  name   = "${var.project_name}-ops-assume-operator"
  group  = aws_iam_group.ops.name
  policy = data.aws_iam_policy_document.ops_assume_operator.json
}

# ── Self-service MFA + MFA guard for human (console) users ──────────────────
data "aws_iam_policy_document" "self_service_mfa" {
  statement {
    sid    = "manageOwnMfa"
    effect = "Allow"
    actions = [
      "iam:CreateVirtualMFADevice", "iam:DeleteVirtualMFADevice",
      "iam:EnableMFADevice", "iam:DisableMFADevice", "iam:ResyncMFADevice",
      "iam:ListVirtualMFADevices", "iam:GetUser",
      "iam:ChangePassword",
    ]
    resources = [
      "arn:aws:iam::${var.account_id}:mfa/$${aws:username}",
      "arn:aws:iam::${var.account_id}:user/$${aws:username}",
    ]
  }
}

resource "aws_iam_policy" "self_service_mfa" {
  name        = "${var.project_name}-self-svc-mfa"
  description = "Let an IAM user manage their own MFA device and password."
  policy      = data.aws_iam_policy_document.self_service_mfa.json
}

# Deny non-MFA access to the ops group (humans must present an MFA device).
data "aws_iam_policy_document" "deny_no_mfa" {
  statement {
    sid       = "DenyUnauthenticatedActions"
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]
    condition {
      test     = "BoolIfExists"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["false"]
    }
  }
}

resource "aws_iam_policy" "deny_no_mfa" {
  name        = "${var.project_name}-require-mfa"
  description = "Deny all IAM-user actions unless a virtual MFA device is used."
  policy      = data.aws_iam_policy_document.deny_no_mfa.json
}

resource "aws_iam_group_policy_attachment" "ops_mfa" {
  group      = aws_iam_group.ops.name
  policy_arn = aws_iam_policy.self_service_mfa.arn
}
resource "aws_iam_group_policy_attachment" "ops_deny_mfa" {
  group      = aws_iam_group.ops.name
  policy_arn = aws_iam_policy.deny_no_mfa.arn
}

# ── Account password policy (foundation hardening) ───────────────────────────
resource "aws_iam_account_password_policy" "this" {
  minimum_password_length        = 14
  require_uppercase_characters   = true
  require_lowercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  password_reuse_prevention      = 6
  max_password_age               = 90
}