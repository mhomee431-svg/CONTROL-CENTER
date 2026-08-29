# ── VPC Endpoints — private S3 access (no NAT / internet) ────────────────────
# S3 GATEWAY endpoint: free, keeps backend S3 traffic inside the VPC (there is
# no NAT gateway in the free-tier design). Terraform automatically inserts an
# S3 prefix route into the isolated data route table listed here.
resource "aws_vpc_endpoint" "s3" {
  count             = var.create_s3_gateway_endpoint ? 1 : 0
  vpc_id            = local.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.data.id]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowAllPrincipalS3"
      Effect    = "Allow"
      Principal = "*"
      Action    = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
      Resource  = ["*"]
    }]
  })

  tags = { Name = "${local.name_prefix}-s3-gateway-endpoint" }
}
