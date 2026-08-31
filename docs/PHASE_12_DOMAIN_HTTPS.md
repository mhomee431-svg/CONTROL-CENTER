# PHASE 12 — Domain + HTTPS

Configures the production API domain (`api.hyperlocal.in`) with HTTPS via
Caddy's built-in Let's Encrypt auto-TLS, DNS via Route53 (or manual), secure
HTTP→HTTPS redirects, automatic certificate renewal, and CORS locked to
approved frontend origins.

## Architecture

```
Internet
  │
  │ (port 80 — ACME HTTP-01 challenge + HTTP→HTTPS redirect)
  │ (port 443 — TLS termination)
  ▼
EC2 (t3.micro, Elastic IP)
  ├─ Caddy (systemd) :80/:443
  │     ├── Auto-TLS: Let's Encrypt cert for api.hyperlocal.in
  │     ├── HTTP → HTTPS redirect (automatic)
  │     ├── Cert renewal: ~30 days before expiry (background, zero-downtime)
  │     ├── encode gzip
  │     ├── Security headers (HSTS, X-Frame-Options, X-Content-Type-Options)
  │     └── reverse_proxy 127.0.0.1:8000
  │
  └─ docker compose (docker-compose.cloud.yml)
       ├─ redis:7-alpine  (local, 127.0.0.1, never host-published)
       ├─ api             (127.0.0.1:8000, --proxy-headers)
       ├─ worker + beat   (Celery)
       └─ migrate (one-shot)
```

No ALB, no NAT, no ACM (cert-manager) — Caddy handles TLS for free on the
free-tier EC2. The domain is `api.hyperlocal.in` with an A-record → the EIP.

## 1. DNS

### Option A: Route53 (managed by Terraform)

Set in `terraform.tfvars`:

```hcl
domain_name          = "api.hyperlocal.in"
dns_zone_name        = "hyperlocal.in."        # Route53 hosted zone apex
manage_dns           = true
```

`infra/terraform/dns.tf` creates an A-record pointing `api.hyperlocal.in`
to the Elastic IP. Caddy uses this to prove domain ownership to Let's Encrypt.

### Option B: External DNS (manual)

If the domain is NOT in Route53, set `manage_dns = false`:

```hcl
domain_name = "api.hyperlocal.in"
manage_dns  = false
```

Then create the A-record at your registrar:

```
api.hyperlocal.in  A  →  <app_public_ip>
```

> **Note**: Let's Encrypt requires DNS to resolve before it can issue a
> certificate. Caddy retries automatically, but the first HTTPS request may
> fail until DNS propagates (~0–60 seconds).

## 2. TLS Certificate (Caddy auto-TLS)

Caddy v2 handles the entire certificate lifecycle automatically:

| Feature | How |
|---|---|
| **Issuance** | Caddy calls Let's Encrypt ACME API (HTTP-01 challenge on port 80) |
| **ACME email** | Set via `caddy_acme_email` variable → Caddyfile global `email` |
| **Storage** | Certificates in `/var/lib/caddy/.local/share/caddy/` (persisted) |
| **Renewal** | Caddy renews ~30 days before expiry, background, zero-downtime |
| **Redirect** | HTTP (port 80) → HTTPS (port 443) redirect is automatic |

### Caddyfile template

`infra/terraform/Caddyfile.tftpl` is rendered by Terraform at `apply` time
and written to `/etc/caddy/Caddyfile` by the boot script. When `domain_name`
is set, it produces:

```caddy
{
    email admin@hyperlocal.in
}

api.hyperlocal.in {
    encode gzip
    reverse_proxy 127.0.0.1:8000 {
        header_up X-Forwarded-Proto https
        header_up X-Forwarded-Host {host}
        header_up X-Real-IP {remote}
    }
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "DENY"
        Referrer-Policy "strict-origin-when-cross-origin"
        X-XSS-Protection "1; mode=block"
    }
}
```

When `domain_name` is empty (development / pre-DNS), it falls back to plain HTTP:

```caddy
:80 {
    encode gzip
    reverse_proxy 127.0.0.1:8000
}
```

## 3. HTTPS

Caddy terminates TLS at the edge and proxies to the FastAPI backend on
`127.0.0.1:8000` (never host-published). The backend sees:

- `X-Forwarded-Proto: https` → sets HSTS, generates HTTPS OAuth callback URLs
- `X-Real-IP` → correct client IP for rate limiting and logging
- `TRUST_X_FORWARDED_FOR=true` in the backend `.env` → rate limiter trusts
  the forwarded chain

### No domain hardcoded in backend logic

The backend derives all domain-dependent values from environment variables:

| Setting | Source |
|---|---|
| `FRONTEND_URL` | `frontend_domain` Terraform variable → boot `.env` |
| `BACKEND_URL` | `domain_name` Terraform variable → boot `.env` |
| `GOOGLE_CALLBACK_URL` | `https://<domain_name>/api/auth/google/callback` |
| `CORS_ORIGINS` | `frontend_domain` + `admin_frontend_domain` → boot `.env` |

The startup security gate (`startup_checks.py`) **refuses to boot in production**
if CORS is `*`, empty, or uses `http://` origins.

## 4. Reverse proxy

Caddy (systemd service) is the reverse proxy:

- Installed by `user_data.sh.tpl` (apt package from Caddy's apt repo)
- Listens on :80 and :443 (security group allows both)
- Proxies to `127.0.0.1:8000` (Docker compose binds only to localhost)
- `restart: unless-stopped` on the `api` container; `systemctl enable caddy`
  on the host — both survive reboots

## 5. Secure redirects (HTTP → HTTPS)

When a domain is configured, Caddy automatically:

1. Serves `:80` with a 301 redirect to `https://<domain>`
2. Serves `:443` with TLS (auto-provisioned)

No additional configuration is needed — this is Caddy's default behavior
for domain-based site blocks.

## 6. Certificate renewal

Caddy handles this automatically:

- A background goroutine checks all certificates daily
- Renews 30 days before expiry (default: 90-day Let's Encrypt certs)
- Uses the same ACME account (registered with the `email` from the Caddyfile)
- **No cron job, no certbot, no manual intervention**

To verify after renewal:

```bash
# Check Caddy's certificate storage
ls /var/lib/caddy/.local/share/caddy/certificates/
# Manually reload (drains connections gracefully)
caddy fmt --overwrite /etc/caddy/Caddyfile && systemctl reload caddy
```

## 7. CORS configuration

CORS origins are **not hardcoded** in backend code. They are derived from
Terraform variables and written to the production `.env` by the boot script:

```hcl
# terraform.tfvars
frontend_domain       = "app.hyperlocal.in"
admin_frontend_domain = "admin.hyperlocal.in"
```

The boot script generates:

```env
CORS_ORIGINS=https://app.hyperlocal.in,https://admin.hyperlocal.in,https://api.hyperlocal.in
```

- `app.hyperlocal.in` — customer Flutter app origin
- `admin.hyperlocal.in` — shopkeeper/admin panel origin
- `api.hyperlocal.in` — allows same-origin health checks through Caddy

The FastAPI app (`main.py`) reads `CORS_ORIGINS` from config and passes
`allow_origins=settings.cors_origin_list, allow_credentials=True`.

The startup security gate blocks production if CORS is `*`, empty, or
contains `http://` origins.

## 8. Terraform configuration

### `terraform.tfvars` (production)

```hcl
# Phase 12 — Production API domain + HTTPS
domain_name            = "api.hyperlocal.in"
caddy_acme_email       = "admin@hyperlocal.in"
frontend_domain        = "app.hyperlocal.in"
admin_frontend_domain  = "admin.hyperlocal.in"
dns_zone_name          = "hyperlocal.in."
manage_dns             = true
```

### `terraform apply` (when updating the domain)

```bash
cd infra/terraform
terraform init        # (once)
terraform plan        # review
terraform apply       # applies — boot script re-runs with the new Caddyfile
```

Because `user_data_replace_on_change = true`, changing the domain or email
triggers a new EC2 launch. For live config updates without replacement:

```bash
# On the EC2 (via Session Manager)
sudo caddy fmt --overwrite /etc/caddy/Caddyfile && sudo systemctl reload caddy
```

## 9. Deploy script (Phase 12 additions)

`infra/scripts/deploy_backend.sh` now supports an optional `DOMAIN_URL`
environment variable for HTTPS verification:

```bash
DOMAIN_URL=https://api.hyperlocal.in ./deploy_backend.sh verify
```

This adds checks for:
- HTTP → HTTPS redirect
- TLS certificate validity (dates + subject)
- HTTPS /health endpoint
- CORS headers on the live HTTPS endpoint

## 10. External verification

Run `infra/scripts/phase12_verify.ps1` from **outside** the EC2 (your laptop):

```powershell
powershell -ExecutionPolicy Bypass -File infra/scripts/phase12_verify.ps1 `
  -ApiUrl https://api.hyperlocal.in `
  -FrontendUrl https://app.hyperlocal.in
```

Checks:
1. DNS — A-record resolves
2. HTTP → HTTPS redirect (301/302/308 to https://)
3. HTTPS certificate — valid, correct subject, not expired
4. API availability — HTTPS root returns 200
5. Health endpoint — GET /health → 200
6. Readiness endpoint — GET /ready → 200 with DB/Redis/PostGIS checks
7. CORS — approved origin gets `Access-Control-Allow-Origin`; random origin does not
8. Security headers — HSTS, X-Frame-Options, X-Content-Type-Options

## 11. Verification checklist

| Check | Method | Status |
|---|---|---|
| HTTP → HTTPS | `phase12_verify.ps1` step 2 / `deploy_backend.sh verify` with `DOMAIN_URL` | ✅ |
| HTTPS certificate | Caddy auto-TLS; `openssl s_client -connect` | ✅ |
| DNS | Route53 A-record → EIP / `dig`/`nslookup` | ✅ |
| API availability | `curl https://api.hyperlocal.in/` | ✅ |
| CORS | `phase12_verify.ps1` step 7 | ✅ |
| Health endpoint | `curl https://api.hyperlocal.in/health` | ✅ |
| Certificate renewal | Caddy background goroutine (auto) | ✅ |

## 12. Backend tests

```bash
cd Backend
python -m pytest tests/test_phase12_domain_https.py -v
```

Tests:
- `test_production_frontend_url_is_https` — FRONTEND_URL uses HTTPS in prod
- `test_production_backend_url_is_https` — BACKEND_URL uses HTTPS in prod
- `test_production_google_callback_is_https` — OAuth callback uses HTTPS
- `test_production_cors_uses_https_only` — all CORS origins are HTTPS
- `test_production_cors_does_not_include_localhost` — no localhost in prod CORS
- `test_production_cors_does_not_wildcard` — no `*` in CORS
- `test_no_hardcoded_domain_in_backend_logic` — source scan for hardcoded domains
- `test_no_example_com_in_backend_logic` — source scan for example.com
- `test_production_hsts_configured` — HSTS headers enabled
- `test_production_trust_x_forwarded_for` — behind reverse proxy
- `test_caddyfile_has_tls_when_domain_set` — Caddyfile template with TLS
- `test_caddyfile_has_no_tls_when_domain_empty` — Caddyfile fallback to HTTP
- `test_caddyfile_redirect_when_domain_set` — domain-based redirect
- `test_health_router_has_health_and_ready` — health endpoints registered
- `test_health_check_returns_status_and_version` — health response format
- `test_main_app_includes_health_router` — health router in main app
- `test_production_settings_have_no_localhost_defaults` — no localhost in prod URLs
- `test_production_cors_includes_api_domain` — API domain in CORS for health checks

## 13. Rollout order

1. **Set domain + DNS**: Update `terraform.tfvars` → `terraform apply`
2. **Wait for DNS**: `nslookup api.hyperlocal.in` → returns the EIP
3. **Wait for Caddy auto-TLS**: Caddy obtains the certificate (1–5 minutes)
4. **Verify**: `./deploy_backend.sh verify` with `DOMAIN_URL=https://api.hyperlocal.in`
5. **External check**: `phase12_verify.ps1 -ApiUrl https://api.hyperlocal.in`
6. **Frontend**: Update the Flutter app's `API_BASE_URL` to `https://api.hyperlocal.in/v1`
