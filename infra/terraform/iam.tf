# ── IAM — task execution & application roles (no static keys) ───────────────

data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# ── Task EXECUTION role: pull ECR image, read Secrets (for injection), logs ─
resource "aws_iam_role" "task_execution" {
  name               = "${local.name_prefix}-ecs-task-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
  tags               = { Name = "${local.name_prefix}-task-exec-role" }
}

resource "aws_iam_role_policy" "task_execution" {
  name = "${local.name_prefix}-task-exec-policy"
  role = aws_iam_role.task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
      {
        Effect   = "Allow",
        Action   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"],
        Resource = [aws_ecr_repository.backend.arn]
      },
      {
        Effect   = "Allow",
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"],
        Resource = ["arn:aws:logs:*:*:*"]
      },
      {
        Effect   = "Allow",
        Action   = ["secretsmanager:GetSecretValue"],
        Resource = [aws_secretsmanager_secret.backend.arn]
      },
      { Effect = "Allow", Action = ["kms:Decrypt"], Resource = [aws_kms_key.this.arn] }
    ]
  })
}

# ── Task RUNTIME role (what the app code actually does) ────────────────────
resource "aws_iam_role" "task" {
  name               = "${local.name_prefix}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
  tags               = { Name = "${local.name_prefix}-task-role" }
}

resource "aws_iam_policy" "runtime" {
  name        = "${local.name_prefix}-runtime"
  description = "S3 + Secrets hydration + outbound providers for the app code"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["s3:ListBucket"],
        Resource = [aws_s3_bucket.uploads.arn]
      },
      {
        Effect   = "Allow",
        Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"],
        Resource = ["${aws_s3_bucket.uploads.arn}/*"]
      },
      {
        # Startup hydration helper (app/core/aws_secrets.py).
        Effect   = "Allow",
        Action   = ["secretsmanager:GetSecretValue"],
        Resource = [aws_secretsmanager_secret.backend.arn]
      },
      { Effect = "Allow", Action = ["kms:Decrypt"], Resource = [aws_kms_key.this.arn] },
      {
        Effect = "Allow",
        Action = ["ses:SendEmail", "ses:SendRawEmail", "sns:Publish"],
        Resource = ["*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "task_exec_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "task_runtime" {
  role       = aws_iam_role.task.name
  policy_arn = aws_iam_policy.runtime.arn
}