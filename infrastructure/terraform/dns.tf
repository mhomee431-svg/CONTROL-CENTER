# ── Phase 12 — DNS (Route53) ──────────────────────────────────────────────────
# Points api.<domain> → the app EIP so Caddy can prove domain ownership to
# Let's Encrypt (ACME HTTP-01 challenge) and serve auto-TLS certificates.
#
# If your domain is NOT in Route53, set manage_dns = false and create the
# A-record at your registrar manually:
#   api.<apex>  A-record  →  <app_public_ip>  (from `terraform output -raw app_public_ip`)

data "aws_route53_zone" "primary" {
  count = var.manage_dns && var.domain_name != "" ? 1 : 0
  name         = var.dns_zone_name
  private_zone = false
}

resource "aws_route53_record" "api_a_record" {
  count = var.manage_dns && var.domain_name != "" ? 1 : 0
  zone_id = data.aws_route53_zone.primary[0].zone_id
  name    = var.domain_name
  type    = "A"
  ttl     = 300
  records = [aws_eip.app.public_ip]
}

# Optional: also create a CNAME for the frontend domain if it points to the
# same EIP (useful when the frontend is served by Caddy on the same box).
# Most deployments serve the frontend from S3/CloudFront — leave unset then.
resource "aws_route53_record" "frontend_cname" {
  count = var.manage_dns && var.frontend_domain != "" && var.frontend_serve_via_caddy ? 1 : 0
  zone_id = data.aws_route53_zone.primary[0].zone_id
  name    = var.frontend_domain
  type    = "CNAME"
  ttl     = 300
  records = [aws_eip.app.public_ip]
}
