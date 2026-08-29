# ── VPC Flow Logs — connectivity audit (ACCEPT + REJECT) → CloudWatch ────────
# Lets you verify "only required traffic is allowed": inspect rejected attempts
# and confirm the data tier never accepts inbound from the internet.
# Cost guard: 14-day retention, no KMS customer key (both free-tier safe).

locals {
  flow_log_group = "${local.name_prefix}-vpc-flow"
}

resource "aws_cloudwatch_log_group" "vpc_flow" {
  count             = var.enable_vpc_flow_logs ? 1 : 0
  name              = local.flow_log_group
  retention_in_days = var.flow_log_retention_days
  tags              = { Name = "${local.name_prefix}-vpc-flow-logs" }
}

# Dedicated, least-privilege role for the VPC → CloudWatch flow log publisher.
data "aws_iam_policy_document" "flow_log_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  count              = var.enable_vpc_flow_logs ? 1 : 0
  name               = "${local.name_prefix}-vpc-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_log_assume.json
  tags               = { Name = "${local.name_prefix}-vpc-flow-log-role" }
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_vpc_flow_logs ? 1 : 0
  name  = "${local.name_prefix}-vpc-flow-log-policy"
  role  = aws_iam_role.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogGroups", "logs:DescribeLogStreams"],
        Resource = ["*"]
      }
    ]
  })
}

resource "aws_flow_log" "main" {
  count                    = var.enable_vpc_flow_logs ? 1 : 0
  iam_role_arn             = aws_iam_role.flow_logs[0].arn
  log_destination          = aws_cloudwatch_log_group.vpc_flow[0].arn
  log_destination_type     = "cloud-watch-logs"
  traffic_type             = "ALL"
  vpc_id                   = local.vpc_id
  max_aggregation_interval = 60

  tags = { Name = "${local.name_prefix}-vpc-flow-log" }
}
