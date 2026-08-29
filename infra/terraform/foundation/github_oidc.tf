# ── GitHub Actions → AWS via OIDC (no long-lived CI keys) ────────────────────
# Generates the thumbprint from GitHub's live TLS chain (no hard-coded hex).

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

data "aws_iam_policy_document" "github_actions_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.github_subjects
    }
  }
}

# ── CI/CD deploy role (least privilege: ECR push + ECS rolling update) ──────
resource "aws_iam_role" "ci_deploy" {
  name               = "${var.project_name}-cicd-deploy"
  description        = "Assumed by GitHub Actions (OIDC) to build/push images and roll ECS services. NOT for humans."
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume.json
  tags               = { Name = "${var.project_name}-cicd-deploy", Purpose = "CI-CD GitHub Actions deploy" }
}

data "aws_iam_policy_document" "ci_deploy" {
  statement {
    sid       = "Identity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"] # identity-only; cannot be narrowed
  }

  statement {
    sid       = "ECRToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # GetAuthorizationToken has no resource-scoping
  }

  statement {
    sid    = "ECRPushAndPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
    ]
    resources = ["arn:aws:ecr:${var.aws_region}:${var.account_id}:repository/${var.ecr_repository_name}"]
  }

  statement {
    sid    = "ECSDeploy"
    effect = "Allow"
    actions = [
      "ecs:DescribeTaskDefinition",
      "ecs:RegisterTaskDefinition",
      "ecs:DescribeServices",
      "ecs:DescribeClusters",
      "ecs:UpdateService",
    ]
    resources = [
      "arn:aws:ecs:${var.aws_region}:${var.account_id}:task-definition/${local.prefix}-*",
      "arn:aws:ecs:${var.aws_region}:${var.account_id}:service/${var.ecs_cluster_name}/*",
      "arn:aws:ecs:${var.aws_region}:${var.account_id}:cluster/${var.ecs_cluster_name}",
    ]
  }
}

resource "aws_iam_role_policy" "ci_deploy" {
  name   = "${var.project_name}-cicd-deploy"
  role   = aws_iam_role.ci_deploy.id
  policy = data.aws_iam_policy_document.ci_deploy.json
}
# ── CI/CD "verify" role (read-only) ─────────────────────────────────────────
# Lets GitHub Actions run the Phase 2 Test steps (identity, simulate-principal-
# policy, role-assumption smoke, wildcard audit) WITHOUT any long-lived
# credential. It can only READ IAM + assume the project roles — never modify
# anything, never push images.
resource "aws_iam_role" "ci_verify" {
  name               = "${var.project_name}-cicd-verify"
  description        = "Assumed by GitHub Actions (OIDC) to verify the IAM foundation (read + simulate + assume smoke). Read-only."
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume.json
  tags               = { Name = "${var.project_name}-cicd-verify", Purpose = "CI-CD IAM verification" }
}

data "aws_iam_policy_document" "ci_verify" {
  statement {
    sid       = "Identity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
  statement {
    sid    = "IamReadAndSimulate"
    effect = "Allow"
    actions = [
      "iam:GetRole", "iam:GetRolePolicy", "iam:ListRoles",
      "iam:ListAttachedRolePolicies", "iam:ListRolePolicies",
      "iam:ListPolicies", "iam:GetPolicy", "iam:GetPolicyVersion",
      "iam:SimulatePrincipalPolicy", "iam:SimulateCustomPolicy",
    ]
    resources = ["*"] # IAM List/Get/Simulate do not support resource-level scoping
  }
  statement {
    sid     = "AssumeSmoke"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    resources = [
      aws_iam_role.operator.arn,
      aws_iam_role.monitor.arn,
      aws_iam_role.db_operator.arn,
      aws_iam_role.s3_backup.arn,
    ]
  }
  statement {
    sid       = "EcrSmoke"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # no resource-level ARN
  }
  statement {
    sid       = "AccountPwPolicy"
    effect    = "Allow"
    actions   = ["iam:GetAccountPasswordPolicy"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ci_verify" {
  name   = "${var.project_name}-cicd-verify"
  role   = aws_iam_role.ci_verify.id
  policy = data.aws_iam_policy_document.ci_verify.json
}