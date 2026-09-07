"""
Phase 12 — Domain + HTTPS verification tests.
"""
import os
import re
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(BACKEND_DIR))
os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

import pytest
from app.core.config import Settings


def _prod_settings(**overrides) -> Settings:
    base = dict(
        ENVIRONMENT="production",
        JWT_SECRET_KEY="x" * 48,
        OTP_DEV_MODE=False,
        DEBUG=False,
        CORS_ORIGINS="https://app.hyperlocal.in,https://admin.hyperlocal.in,https://api.hyperlocal.in",
        FRONTEND_URL="https://app.hyperlocal.in",
        BACKEND_URL="https://api.hyperlocal.in",
        TRUST_X_FORWARDED_FOR=True,
        GOOGLE_CALLBACK_URL="https://api.hyperlocal.in/api/auth/google/callback",
    )
    base.update(overrides)
    return Settings(**base)


# -- 1. Production uses HTTPS for frontend/backend URLs --

def test_production_frontend_url_is_https():
    s = _prod_settings()
    assert s.FRONTEND_URL.startswith("https://"), (
        f"FRONTEND_URL must be HTTPS in production, got: {s.FRONTEND_URL}"
    )


def test_production_backend_url_is_https():
    s = _prod_settings()
    assert s.BACKEND_URL.startswith("https://"), (
        f"BACKEND_URL must be HTTPS in production, got: {s.BACKEND_URL}"
    )


def test_production_google_callback_is_https():
    s = _prod_settings()
    assert s.GOOGLE_CALLBACK_URL.startswith("https://"), (
        f"GOOGLE_CALLBACK_URL must be HTTPS in production, got: {s.GOOGLE_CALLBACK_URL}"
    )


# -- 2. CORS origins are explicitly configured with HTTPS --

def test_production_cors_uses_https_only():
    s = _prod_settings()
    for origin in s.cors_origin_list:
        assert origin.startswith("https://"), (
            f"All CORS origins must be HTTPS in production, found: {origin}"
        )


def test_production_cors_does_not_include_localhost():
    s = _prod_settings()
    for origin in s.cors_origin_list:
        assert "localhost" not in origin, (
            f"CORS origin must not include localhost in production: {origin}"
        )


def test_production_cors_does_not_wildcard():
    s = _prod_settings()
    origins = s.cors_origin_list
    assert "*" not in origins, "CORS must not be * in production"
    assert len(origins) > 0, "CORS_ORIGINS must be non-empty in production"


# -- 3. No domain is hardcoded in backend logic --

FORBIDDEN_DOMAIN_PATTERNS = [
    r"api\.hyperlocal\.in",
    r"app\.hyperlocal\.in",
    r"admin\.hyperlocal\.in",
    r"api\.example\.com",
]
SCAN_DIRS = [BACKEND_DIR / "app"]
EXCLUDE_SUBSTRINGS = ["/core/config.py", "/repositories/", os.sep + "repositories" + os.sep]


def _scan_for_hardcoded_domains():
    findings = []
    for scan_dir in SCAN_DIRS:
        if not scan_dir.exists():
            continue
        for pyfile in scan_dir.rglob("*.py"):
            rel = str(pyfile.relative_to(BACKEND_DIR))
            if any(ex in rel for ex in EXCLUDE_SUBSTRINGS):
                continue
            try:
                file_lines = pyfile.read_text(encoding="utf-8", errors="replace").splitlines()
            except OSError:
                continue
            for i, line in enumerate(file_lines, 1):
                for pattern in FORBIDDEN_DOMAIN_PATTERNS:
                    if re.search(pattern, line):
                        findings.append((str(pyfile.relative_to(REPO_ROOT)), i, line.strip()))
    return findings

def test_no_hardcoded_domain_in_backend_logic():
    findings = _scan_for_hardcoded_domains()
    assert findings == [], (
        f"Hardcoded domains found in backend logic:\n"
        + "\n".join(f"  {f[0]}:{f[1]}: {f[2]}" for f in findings)
    )


def test_no_example_com_in_backend_logic():
    findings = []
    for scan_dir in SCAN_DIRS:
        if not scan_dir.exists():
            continue
        for pyfile in scan_dir.rglob("*.py"):
            rel = str(pyfile.relative_to(BACKEND_DIR))
            if any(ex in rel for ex in EXCLUDE_SUBSTRINGS):
                continue
            try:
                file_lines = pyfile.read_text(encoding="utf-8", errors="replace").splitlines()
            except OSError:
                continue
            for i, line in enumerate(file_lines, 1):
                if "example.com" in line and not line.strip().startswith("#"):
                    findings.append((str(pyfile.relative_to(REPO_ROOT)), i, line.strip()))
    assert findings == [], (
        f"example.com found in backend source:\n"
        + "\n".join(f"  {f[0]}:{f[1]}: {f[2]}" for f in findings)
    )


# -- 4. Security headers (HSTS) configured --

def test_production_hsts_configured():
    s = _prod_settings()
    assert s.SECURITY_HEADERS_ENABLED is True
    assert s.HSTS_MAX_AGE > 0
    assert s.HSTS_INCLUDE_SUBDOMAINS is True
    assert s.HSTS_PRELOAD is True


# -- 5. TRUST_X_FORWARDED_FOR --

def test_production_trust_x_forwarded_for():
    s = _prod_settings()
    assert s.TRUST_X_FORWARDED_FOR is True, (
        "TRUST_X_FORWARDED_FOR must be True behind Caddy reverse proxy in production"
    )


# -- 6. Caddyfile template renders correctly --

@pytest.fixture
def caddyfile_template_path():
    return REPO_ROOT / "infrastructure" / "terraform" / "Caddyfile.tftpl"


def _render_caddyfile(template_path, domain_name, acme_email):
    """Render the Caddyfile template with variable substitution for testing.
    Uses string splitting instead of regex to avoid escaping issues."""
    template = template_path.read_text(encoding="utf-8")
    result = template.replace("${domain_name}", domain_name)
    result = result.replace("${acme_email}", acme_email)
    if_marker = '%{ if domain_name != "" }'
    else_marker = "%{ else }"
    end_marker = "%{ endif %}"
    if if_marker in result:
        parts = result.split(else_marker)
        before_else = parts[0].split(if_marker)
        after_else = parts[1].split(end_marker)
        if domain_name:
            result = before_else[1]
        else:
            result = after_else[0]
    return result.strip()


def test_caddyfile_has_tls_when_domain_set(caddyfile_template_path):
    rendered = _render_caddyfile(caddyfile_template_path, "api.hyperlocal.in", "admin@hyperlocal.in")
    assert "api.hyperlocal.in" in rendered
    assert "email admin@hyperlocal.in" in rendered
    assert "encode gzip" in rendered
    assert "reverse_proxy 127.0.0.1:8000" in rendered
    assert "X-Forwarded-Proto https" in rendered
    assert "Strict-Transport-Security" in rendered


def test_caddyfile_has_no_tls_when_domain_empty(caddyfile_template_path):
    rendered = _render_caddyfile(caddyfile_template_path, "", "")
    assert ":80" in rendered
    assert "reverse_proxy 127.0.0.1:8000" in rendered
    assert "Strict-Transport-Security" not in rendered


def test_caddyfile_redirect_when_domain_set(caddyfile_template_path):
    rendered = _render_caddyfile(caddyfile_template_path, "api.hyperlocal.in", "admin@hyperlocal.in")
    assert "api.hyperlocal.in" in rendered
    assert "Strict-Transport-Security" in rendered


# -- 7. Health / readiness endpoints registered --

def test_health_router_has_health_and_ready():
    from app.core.health import router
    routes = {r.path for r in router.routes}
    assert "/health" in routes
    assert "/ready" in routes


def test_health_check_returns_status_and_version():
    from app.core.health import health_check
    import asyncio
    result = asyncio.run(health_check())
    assert "status" in result
    assert result["status"] == "healthy"
    assert "version" in result
    assert "environment" in result


def test_main_app_includes_health_router():
    from app.main import app
    assert app.url_path_for("health_check") == "/health"
    assert app.url_path_for("readiness_check") == "/ready"


# -- 8. Domain-driven config validation --

def test_production_settings_have_no_localhost_defaults():
    s = _prod_settings()
    assert "localhost" not in s.FRONTEND_URL
    assert "localhost" not in s.BACKEND_URL
    assert "localhost" not in s.GOOGLE_CALLBACK_URL


def test_production_cors_includes_api_domain():
    s = _prod_settings()
    origins = s.cors_origin_list
    assert any("api.hyperlocal.in" in o for o in origins), (
        f"API domain should be in CORS origins, got: {origins}"
    )
