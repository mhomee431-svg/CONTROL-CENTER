# ── DNS & TLS (ACM certificate + Route53 records) ───────────────────────────

locals {
  # Used by ecs.tf HTTPS listener. If you bring your own cert, set
  # acm_certificate_arn and create_acm_certificate=false.
  cert_arn = var.create_acm_certificate
    ? aws_acm_certificate.next[0].arn
    : var.acm_certificate_arn
}

resource "aws_acm_certificate" "next" {
  count             = var.create_acm_certificate ? 1 : 0
  domain_name       = "${var.api_subdomain}.${var.domain_name}"
  validation_method = "DNS"
  tags              = { Name = "${local.name_prefix}-cert" }

  lifecycle {
    create_before_destroy = true
  }
}

# DNS validation + public A (alias to ALB) — only when the zone is in Route53.
resource "aws_route53_record" "cert_validation" {
  count   = (var.create_acm_certificate && var.create_route53_records) ? 1 : 0
  zone_id = var.hosted_zone_id
  name    = aws_acm_certificate.next[0].domain_validation_options.0.resource_record_name
  type    = aws_acm_certificate.next[0].domain_validation_options.0.resource_record_type
  records = [aws_acm_certificate.next[0].domain_validation_options.0.resource_record_value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "next" {
  count                   = var.create_acm_certificate ? 1 : 0
  certificate_arn         = aws_acm_certificate.next[0].arn
  validation_record_fqdns = var.create_route53_records
    ? [aws_route53_record.cert_validation[0].fqdn]
    : []
}

# Public A record → ALB.
resource "aws_route53_record" "alb" {
  count   = var.create_route53_records ? 1 : 0
  zone_id = var.hosted_zone_id
  name    = var.api_subdomain
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}