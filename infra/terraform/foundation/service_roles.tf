# ── Purpose-specific supporting roles (least privilege, role-based) ─────────

# Shared trust: the account's internal principals may assume these roles, and
# optionally additional operator principals. (Console/SSO users assume them via
# an operator session; no long-lived keys are used.)
data "aws_iam_policy_document" "ops_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type = "AWS"
      identifiers = concat(
        ["arn:aws:iam::${var.account_id}:root"],
        var.operator_principals,
      )
    }
  }
}

# ═══ Monitoring (read-only) ─────────────────────────────────────────────────
data "aws_iam_policy_document" "monitor" {
  statement {
    sid       = "Identity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
  statement {
    sid    = "CloudWatchRead"
    effect = "Allow"
    actions = [
      "cloudwatch:ListMetrics", "cloudwatch:GetMetricStatistics",
      "cloudwatch:DescribeAlarms", "cloudwatch:DescribeAlarmHistory",
      "cloudwatch:GetMetricData",
    ]
    resources = ["*"] # CloudWatch has no resource-level policy keys for read metrics
  }
  statement {
    sid       = "LogsReadScoped"
    effect    = "Allow"
    actions   = ["logs:DescribeLogGroups", "logs:DescribeLogStreams", "logs:GetLogEvents", "logs:FilterLogEvents"]
    resources = ["arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:/ecs/${local.prefix}*"]
  }
  statement {
    sid    = "EcsRead"
    effect = "Allow"
    actions = [
      "ecs:DescribeClusters", "ecs:DescribeServices", "ecs:ListServices",
      "ecs:DescribeTaskDefinition", "ecs:DescribeTasks", "ecs:ListTasks",
    ]
    resources = [
      "arn:aws:ecs:${var.aws_region}:${var.account_id}:cluster/${var.ecs_cluster_name}",
      "arn:aws:ecs:${var.aws_region}:${var.account_id}:service/${var.ecs_cluster_name}/*",
      "arn:aws:ecs:${var.aws_region}:${var.account_id}:task-definition/${local.prefix}-*",
    ]
  }
  statement {
    sid       = "AlarmsRead"
    effect    = "Allow"
    actions   = ["sns:ListTopics", "sns:GetTopicAttributes"]
    resources = ["arn:aws:sns:${var.aws_region}:${var.account_id}:*"]
  }
}

resource "aws_iam_role" "monitor" {
  name               = "${var.project_name}-monitor"
  description        = "Read-only monitoring role (CloudWatch, ECS logs, alarms). Assumed by human/ops principals."
  assume_role_policy = data.aws_iam_policy_document.ops_trust.json
  tags               = { Name = "${var.project_name}-monitor", Purpose = "Monitoring" }
}

resource "aws_iam_role_policy" "monitor" {
  name   = "${local.prefix}-monitor"
  role   = aws_iam_role.monitor.id
  policy = data.aws_iam_policy_document.monitor.json
}

# ═══ Database operator (control-plane only; no DB password exposure) ────────
data "aws_iam_policy_document" "db_operator" {
  statement {
    sid    = "RdsReadMaintenance"
    effect = "Allow"
    actions = [
      "rds:DescribeDBInstances", "rds:DescribeDBClusters",
      "rds:RebootDBInstance", "rds:StartDBInstance", "rds:StopDBInstance",
      "rds:CreateDBSnapshot", "rds:DescribeDBSnapshots", "rds:DeleteDBSnapshot",
      "rds:DescribeDBInstanceAutomatedBackups", "rds:DescribeDBParameterGroups",
    ]
    resources = [
      "arn:aws:rds:${var.aws_region}:${var.account_id}:db:${local.prefix}-db",
      "arn:aws:rds:${var.aws_region}:${var.account_id}:snapshot:${local.prefix}-*",
      "arn:aws:rds:${var.aws_region}:${var.account_id}:og:${local.prefix}-*",
      "arn:aws:rds:${var.aws_region}:${var.account_id}:subgrp:${local.prefix}-*",
    ]
  }
}

resource "aws_iam_role" "db_operator" {
  name               = "${var.project_name}-db-operator"
  description        = "Manage RDS lifecycle (reboot/snapshot/start-stop). Does NOT grant psql access; credentials stay in Secrets Manager."
  assume_role_policy = data.aws_iam_policy_document.ops_trust.json
  tags               = { Name = "${var.project_name}-db-operator", Purpose = "Database administration" }
}

resource "aws_iam_role_policy" "db_operator" {
  name   = "${local.prefix}-db-operator"
  role   = aws_iam_role.db_operator.id
  policy = data.aws_iam_policy_document.db_operator.json
}

# ═══ S3 backup / export role (scoped, read + write to an archive path) ──────
data "aws_iam_policy_document" "s3_backup" {
  statement {
    sid     = "ReadAppAndState"
    effect  = "Allow"
    actions = ["s3:ListBucket", "s3:GetObject", "s3:GetObjectVersion", "s3:GetBucketVersioning"]
    resources = [
      aws_s3_bucket.tf_state.arn,
      "${aws_s3_bucket.tf_state.arn}/*",
      "arn:aws:s3:::${local.prefix}-uploads",
      "arn:aws:s3:::${local.prefix}-uploads/*",
    ]
  }
  statement {
    sid       = "WriteArchive"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${local.prefix}-uploads/archive/*"]
  }
}

resource "aws_iam_role" "s3_backup" {
  name               = "${var.project_name}-s3-backup"
  description        = "Read bucket content and write to the archive prefix for operational backups."
  assume_role_policy = data.aws_iam_policy_document.ops_trust.json
  tags               = { Name = "${var.project_name}-s3-backup", Purpose = "S3 backup" }
}

resource "aws_iam_role_policy" "s3_backup" {
  name   = "${local.prefix}-s3-backup"
  role   = aws_iam_role.s3_backup.id
  policy = data.aws_iam_policy_document.s3_backup.json
}