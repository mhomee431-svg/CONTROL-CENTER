# ── Human / infra-administration bootstrap (least privilege, roles > keys) ──
# The ONLY long-lived credential is a small IAM *bootstrap* user whose entire
# policy is "assume the operator role". Everything else is role-based.

# ── Operator role trust: ONLY the listed principals (bootstrap + configured) ─
data "aws_iam_policy_document" "operator_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = local.operator_principals
    }
  }
}

resource "aws_iam_role" "operator" {
  name               = "${var.project_name}-operator"
  description        = "Infrastructure operator (Terraform). Least privilege, project-scoped. No 'iam:*' / admin grants."
  assume_role_policy = data.aws_iam_policy_document.operator_assume.json
  tags               = { Name = "${var.project_name}-operator", Purpose = "Infrastructure administration" }
}

# ═══ 1 — compute & networking ──────────────────────────────────────────────
data "aws_iam_policy_document" "operator_compute" {
  statement {
    sid    = "ec2vpc"
    effect = "Allow"
    actions = [
      "ec2:DescribeVpcs", "ec2:CreateVpc", "ec2:DeleteVpc",
      "ec2:DescribeSubnets", "ec2:CreateSubnet", "ec2:DeleteSubnet",
      "ec2:DescribeInternetGateways", "ec2:CreateInternetGateway", "ec2:AttachInternetGateway",
      "ec2:DescribeNatGateways", "ec2:CreateNatGateway", "ec2:DeleteNatGateway",
      "ec2:AllocateAddress", "ec2:ReleaseAddress", "ec2:DescribeAddresses",
      "ec2:DescribeRouteTables", "ec2:CreateRouteTable", "ec2:DeleteRouteTable",
      "ec2:CreateRoute", "ec2:DeleteRoute", "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable",
      "ec2:DescribeSecurityGroups", "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress", "ec2:RevokeSecurityGroupEgress",
      "ec2:DescribeNetworkInterfaces", "ec2:DescribeInstances", "ec2:DescribeVpcAttribute",
      "ec2:DescribeAvailabilityZones", "ec2:DescribeAccountAttributes",
      "ec2:CreateTags", "ec2:DeleteTags", "ec2:DescribeTags",
    ]
    resources = ["*"] # EC2 does not support resource-level ARNs for most of these actions
  }

  statement {
    sid    = "ecs"
    effect = "Allow"
    actions = [
      "ecs:CreateCluster", "ecs:DeleteCluster", "ecs:DescribeClusters",
      "ecs:RegisterTaskDefinition", "ecs:DeregisterTaskDefinition", "ecs:DescribeTaskDefinition",
      "ecs:CreateService", "ecs:UpdateService", "ecs:DeleteService", "ecs:DescribeServices",
      "ecs:ListServices", "ecs:RunTask", "ecs:StopTask", "ecs:DescribeTasks", "ecs:ListTasks",
    ]
    resources = [
      "arn:aws:ecs:${var.aws_region}:${var.account_id}:cluster/${var.ecs_cluster_name}",
      "arn:aws:ecs:${var.aws_region}:${var.account_id}:service/${var.ecs_cluster_name}/*",
      "arn:aws:ecs:${var.aws_region}:${var.account_id}:task-definition/${local.prefix}-*",
    ]
  }

  statement {
    sid       = "EcrToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # GetAuthorizationToken has no resource-level ARN scope
  }

  statement {
    sid    = "ecr"
    effect = "Allow"
    actions = [
      "ecr:CreateRepository", "ecr:DeleteRepository", "ecr:DescribeRepositories",
      "ecr:GetLifecyclePolicy", "ecr:PutLifecyclePolicy", "ecr:DeleteLifecyclePolicy",
      "ecr:PutRepositoryPolicy", "ecr:GetRepositoryPolicy",
      "ecr:PutImage", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload",
    ]
    resources = ["arn:aws:ecr:${var.aws_region}:${var.account_id}:repository/${var.ecr_repository_name}"]
  }

  statement {
    sid    = "elb"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:CreateLoadBalancer", "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:CreateListener", "elasticloadbalancing:DeleteListener", "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:CreateTargetGroup", "elasticloadbalancing:DeleteTargetGroup", "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:RegisterTargets", "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:ModifyTargetGroupAttributes", "elasticloadbalancing:DescribeLoadBalancers",
    ]
    resources = [
      "arn:aws:elasticloadbalancing:${var.aws_region}:${var.account_id}:loadbalancer/app/${local.prefix}-*",
      "arn:aws:elasticloadbalancing:${var.aws_region}:${var.account_id}:targetgroup/${local.prefix}-*",
      "arn:aws:elasticloadbalancing:${var.aws_region}:${var.account_id}:listener/app/${local.prefix}-*/*/*",
    ]
  }
}
# ═══ 2 — data plane (RDS / ElastiCache / S3 / Secrets / KMS) ────────────────
data "aws_iam_policy_document" "operator_data" {
  statement {
    sid    = "rds"
    effect = "Allow"
    actions = [
      "rds:DescribeDBInstances", "rds:ModifyDBInstance", "rds:RebootDBInstance",
      "rds:StartDBInstance", "rds:StopDBInstance",
      "rds:DescribeDBSubnetGroups", "rds:DescribeDBParameterGroups", "rds:ModifyDBParameterGroup",
      "rds:CreateDBSnapshot", "rds:DescribeDBSnapshots", "rds:DeleteDBSnapshot", "rds:RestoreDBInstanceFromDBSnapshot",
      "rds:DescribeDBInstanceAutomatedBackups",
    ]
    resources = [
      "arn:aws:rds:${var.aws_region}:${var.account_id}:db:${local.prefix}-db",
      "arn:aws:rds:${var.aws_region}:${var.account_id}:snapshot:${local.prefix}-*",
      "arn:aws:rds:${var.aws_region}:${var.account_id}:og:${local.prefix}-*",
      "arn:aws:rds:${var.aws_region}:${var.account_id}:subgrp:${local.prefix}-*",
    ]
  }

  statement {
    sid       = "elasticache"
    effect    = "Allow"
    actions   = ["elasticache:DescribeCacheClusters", "elasticache:ModifyCacheCluster", "elasticache:RebootCacheCluster", "elasticache:DescribeCacheSubnetGroups"]
    resources = ["arn:aws:elasticache:${var.aws_region}:${var.account_id}:cluster:${local.prefix}-redis"]
  }

  statement {
    sid    = "s3"
    effect = "Allow"
    actions = [
      "s3:CreateBucket", "s3:PutBucketVersioning", "s3:GetBucketVersioning",
      "s3:PutBucketEncryption", "s3:GetBucketEncryption",
      "s3:PutBucketPublicAccessBlock", "s3:GetBucketPublicAccessBlock",
      "s3:PutBucketPolicy", "s3:GetBucketPolicy", "s3:DeleteBucketPolicy",
      "s3:PutBucketLifecycleConfiguration", "s3:GetBucketLifecycleConfiguration",
      "s3:PutBucketTagging", "s3:GetBucketTagging",
      "s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject",
      "s3:GetBucketLocation",
    ]
    resources = [
      aws_s3_bucket.tf_state.arn,
      "${aws_s3_bucket.tf_state.arn}/*",
      "arn:aws:s3:::${local.prefix}-uploads", # app uploads bucket (app module)
      "arn:aws:s3:::${local.prefix}-uploads/*",
    ]
  }

  statement {
    sid    = "secrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue", "secretsmanager:PutSecretValue",
      "secretsmanager:DescribeSecret", "secretsmanager:CreateSecret", "secretsmanager:DeleteSecret",
      "secretsmanager:TagResource", "secretsmanager:UntagResource", "secretsmanager:UpdateSecret",
    ]
    resources = [
      "arn:aws:secretsmanager:${var.aws_region}:${var.account_id}:secret:${var.secrets_secret_name}/${var.environment}-*",
      "arn:aws:secretsmanager:${var.aws_region}:${var.account_id}:secret:${var.secrets_secret_name}/${var.environment}/database-*",
    ]
  }

  statement {
    sid    = "kms"
    effect = "Allow"
    actions = [
      "kms:DescribeKey", "kms:GetKeyPolicy", "kms:PutKeyPolicy",
      "kms:EnableKeyRotation", "kms:GetKeyRotationStatus", "kms:Decrypt", "kms:GenerateDataKey",
      "kms:TagResource", "kms:ListResourceTags",
    ]
    resources = ["arn:aws:kms:${var.aws_region}:${var.account_id}:key/*"]
  }
}

# ═══ 3 — edge (ACM / Route53 / logs read) & IAM pass-role ────────────────────
data "aws_iam_policy_document" "operator_edge" {
  statement {
    sid       = "LogsRead"
    effect    = "Allow"
    actions   = ["logs:DescribeLogGroups", "logs:GetLogEvents", "logs:FilterLogEvents", "logs:DescribeLogStreams"]
    resources = ["arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:/ecs/${local.prefix}*"]
  }

  dynamic "statement" {
    for_each = var.hosted_zone_id != "" ? [1] : []
    content {
      sid     = "Route53"
      effect  = "Allow"
      actions = ["route53:ChangeResourceRecordSets", "route53:GetHostedZone", "route53:ListResourceRecordSets"]
      resources = [
        "arn:aws:route53:::hostedzone/${var.hosted_zone_id}",
      ]
    }
  }

  statement {
    sid       = "acm"
    effect    = "Allow"
    actions   = ["acm:RequestCertificate", "acm:DeleteCertificate", "acm:DescribeCertificate", "acm:ListCertificates"]
    resources = ["arn:aws:acm:${var.aws_region}:${var.account_id}:certificate/*"]
  }

  statement {
    sid       = "DynamoDBLock"
    effect    = "Allow"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:DescribeTable"]
    resources = ["arn:aws:dynamodb:${var.aws_region}:${var.account_id}:table/${var.lock_table}"]
  }

  statement {
    sid     = "PassRole"
    effect  = "Allow"
    actions = ["iam:PassRole"]
    resources = [
      "arn:aws:iam::${var.account_id}:role/${local.prefix}-ecs-task-exec",
      "arn:aws:iam::${var.account_id}:role/${local.prefix}-ecs-task",
    ]
  }

  statement {
    sid       = "IAMRead"
    effect    = "Allow"
    actions   = ["iam:GetRole", "iam:GetRolePolicy", "iam:ListRoles", "iam:ListAttachedRolePolicies", "iam:ListRolePolicies"]
    resources = ["arn:aws:iam::${var.account_id}:role/${local.prefix}-*"]
  }
}

# ── Attach the three scoped policies to the operator role ───────────────────
resource "aws_iam_role_policy" "operator_compute" {
  name   = "${local.prefix}-operator-compute"
  role   = aws_iam_role.operator.id
  policy = data.aws_iam_policy_document.operator_compute.json
}

resource "aws_iam_role_policy" "operator_data" {
  name   = "${local.prefix}-operator-data"
  role   = aws_iam_role.operator.id
  policy = data.aws_iam_policy_document.operator_data.json
}

resource "aws_iam_role_policy" "operator_edge" {
  name   = "${local.prefix}-operator-edge"
  role   = aws_iam_role.operator.id
  policy = data.aws_iam_policy_document.operator_edge.json
}