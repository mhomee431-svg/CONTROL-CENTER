"""Phase 24 — Observability verification tests.

Covers the complete observability stack introduced in Phase 24:

* Metrics primitives (counter / gauge / histogram + Prometheus text format)
* Redaction guarantees (passwords, OTPs, tokens, private keys, cards,
  nested dicts — must NEVER reach a sink)
* Structured logging (service labels, request context, key-aware redaction)
* HTTP metrics via the real metrics + access-log middlewares
* DB / Redis / S3 error counters and availability gauges
* Authentication outcome metrics (customer + shopkeeper channels)
* Background-job metrics (Celery signal hooks with a fake task)
* Deployment identity gauges
* Resource sampling (graceful degradation when psutil//proc unavailable)
* Alert engine (firing / resolved lifecycle, deltas, notifiers)
* HTTP routes: ``GET /metrics`` and the admin overview/alerts endpoints
"""

import os
import sys
import time
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")
os.environ.setdefault("LOG_LEVEL", "WARNING")

import pytest  # noqa: E402

# ── Redaction ───────────────────────────────────────────────────────────────


def test_redact_inline_password():
    from app.core.observability.redact import redact_message

    out = redact_message("password=sup3rs3cret1 user=akash")
    assert "sup3rs3cret1" not in out
    assert "[REDACTED]" in out
    assert "user=akash" in out


def test_redact_otp_and_tokens():
    from app.core.observability.redact import redact_message

    assert redact_message("otp: 482913") == "otp: [REDACTED]"
    token = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
    assert token not in redact_message(f"Authorization: Bearer {token}")


def test_redact_private_key_block():
    from app.core.observability.redact import redact_message

    key = "-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAA==\n-----END RSA PRIVATE KEY-----"
    out = redact_message(f"key material:\n{key}")
    assert "MIIEowIBAA" not in out
    assert "[REDACTED]" in out


def test_redact_card_number():
    from app.core.observability.redact import redact_message

    assert "4242 4242 4242 4242" not in redact_message("card 4242 4242 4242 4242 declined")


def test_redact_api_key_and_client_secret():
    from app.core.observability.redact import redact_message

    assert "sk-live-1234567890" not in redact_message("api_key=sk-live-1234567890")
    assert "ABCdef123456" not in redact_message("client_secret=\"ABCdef123456\"")


def test_secret_key_detection():
    from app.core.observability.redact import is_secret_key

    for key in ("otp", "password", "access_token", "api_key", "authorization", "client_secret"):
        assert is_secret_key(key), key
    for key in ("path", "status", "message", "query", "shop_id"):
        assert not is_secret_key(key), key


def test_redact_nested_dict_values():
    from app.core.logging import JsonFormatter

    out = JsonFormatter._redact_recursive(
        {"otp": "482913", "nested": {"client_secret": "ABC123", "ok": True}, "tags": ["a", "b"]}
    )
    assert out["otp"] == "[REDACTED]"
    assert out["nested"]["client_secret"] == "[REDACTED]"
    assert out["nested"]["ok"] is True
    assert out["tags"] == ["a", "b"]


# ── Structured logging ──────────────────────────────────────────────────────


def test_logging_formatter_emits_service_labels_and_redacts():
    import io
    import json
    import logging

    from app.core.logging import JsonFormatter

    logger = logging.getLogger("test.observability.phase24")
    logger.propagate = False
    logger.handlers.clear()
    logger.addHandler(logging.StreamHandler())
    buf = io.StringIO()
    logger.handlers[0].setStream(buf)
    logger.handlers[0].setFormatter(JsonFormatter())
    logger.setLevel(logging.INFO)
    logger.info("login password=hunter2")
    line = buf.getvalue()
    data = json.loads(line)
    assert data["service"] == "hyperlocal-customer-api"
    assert data["environment"] in ("test", "testing")
    assert "hunter2" not in line
    assert "[REDACTED]" in line


def test_logging_extra_data_redacted():
    import io
    import json
    import logging

    from app.core.logging import JsonFormatter

    logger = logging.getLogger("test.observability.extra")
    logger.propagate = False
    logger.handlers.clear()
    logger.addHandler(logging.StreamHandler())
    buf = io.StringIO()
    logger.handlers[0].setStream(buf)
    logger.handlers[0].setFormatter(JsonFormatter())
    logger.setLevel(logging.INFO)
    logger.info(
        "http_request",
        extra={"data": {"event": "http_request", "path": "/api/v1/shops/42", "otp": "111111"}},
    )
    data = json.loads(buf.getvalue())
    assert data["otp"] == "[REDACTED]"
    assert data["path"] == "/api/v1/shops/42"


# ── Metric primitives ───────────────────────────────────────────────────────


def test_counter_and_gauge_semantics():
    from app.core.observability.registry import Counter, Gauge, Registry

    reg = Registry()
    counter = Counter("hl_t_count", "test counter", ["method"], registry=reg)
    gauge = Gauge("hl_t_gauge", "test gauge", registry=reg)
    counter.inc(method="GET")
    counter.inc(method="GET")
    counter.inc(method="POST")
    gauge.set(3.5)
    assert counter.get(method="GET") == 2
    assert counter.get(method="POST") == 1
    assert gauge.get() == 3.5
    rendered = reg.render()
    assert "# TYPE hl_t_count counter" in rendered
    assert 'hl_t_count{method="GET"} 2' in rendered
    assert "hl_t_gauge 3.5" in rendered


def test_histogram_buckets_are_cumulative():
    from app.core.observability.registry import Histogram, Registry

    reg = Registry()
    h = Histogram("hl_t_hist", "test hist", ["x"], buckets=[0.1, 1.0], registry=reg)
    h.observe(0.05, x="a")
    h.observe(2.0, x="a")
    assert h.count(x="a") == 2
    assert abs(h.sum(x="a") - 2.05) < 1e-9
    assert round(h.average(x="a"), 3) == 1.025
    text = reg.render()
    assert 'hl_t_hist_bucket{x="a",le="0.1"} 1' in text
    assert 'hl_t_hist_bucket{x="a",le="1"} 1' in text
    assert 'hl_t_hist_bucket{x="a",le="+Inf"} 2' in text
    assert 'hl_t_hist_sum{x="a"} 2.05' in text


def test_metric_name_and_label_validation():
    from app.core.observability.registry import Counter, Registry

    reg = Registry()
    with pytest.raises(ValueError):
        Counter("bad name!", "help", registry=reg)
    counter = Counter("hl_t_valid", "help", ["method"], registry=reg)
    with pytest.raises(KeyError):
        counter.inc(unexpected_label="x")


def test_registry_rejects_duplicate_names():
    from app.core.observability.registry import Counter, Registry

    reg = Registry()
    Counter("hl_t_dup", "help", registry=reg)
    with pytest.raises(ValueError):
        Counter("hl_t_dup", "help", registry=reg)


def test_normalize_path_bounds_cardinality():
    from app.core.observability.metrics import normalize_path

    assert normalize_path("/api/v1/shops/42/items/7") == "/api/v1/shops/{id}/items/{id}"
    assert normalize_path("/api/v1/search") == "/api/v1/search"


# ── Instrumentation helpers ─────────────────────────────────────────────────


def test_http_metrics_record_request():
    from app.core.observability import metrics

    metrics.record_http_request("GET", "/api/v1/shops/42", 200, 0.05)
    metrics.record_http_request("GET", "/api/v1/shops/42", 503, 1.5)
    metrics.record_http_request("POST", "/api/v1/auth/login", 400, 0.3)
    path = "/api/v1/shops/{id}"
    assert metrics.http_requests_total.get(method="GET", path=path) == 2
    assert metrics.http_5xx_total.get(method="GET", path=path) == 1
    assert metrics.http_errors_total.get(method="GET", path=path, status="503") == 1


def test_db_redis_storage_error_helpers():
    from app.core.observability import metrics

    metrics.record_db_error("statement")
    metrics.record_redis_error("ping")
    metrics.record_storage_operation("upload", "s3", False)
    assert metrics.db_errors_total.get(kind="statement") >= 1
    assert metrics.redis_errors_total.get(op="ping") >= 1
    assert metrics.storage_failures_total.get(op="upload", provider="s3") >= 1
    metrics.set_db_available(True)
    metrics.set_redis_available(False)
    metrics.set_storage_available(True)
    assert metrics.db_available.get() == 1
    assert metrics.redis_available.get() == 0
    assert metrics.storage_available.get() == 1


def test_auth_result_helper():
    from app.core.observability import metrics

    metrics.record_auth_result("otp", False, "invalid_otp")
    metrics.record_auth_result("otp", True, "success")
    metrics.record_auth_result("access_token", False, "missing")
    assert metrics.auth_failures_total.get(channel="otp", reason="invalid_otp") >= 1
    assert metrics.auth_attempts_total.get(channel="otp") >= 2
    assert metrics.auth_failures_total.get(channel="access_token", reason="missing") >= 1


def test_background_job_helpers():
    from app.core.observability import metrics

    metrics.record_background_job("app.services.tasks.dispatch_email", "succeeded")
    metrics.set_background_job_active("app.services.tasks.dispatch_email", True)
    metrics.set_background_job_active("app.services.tasks.dispatch_email", False)
    assert metrics.background_jobs_total.get(
        task="app.services.tasks.dispatch_email", event="succeeded"
    ) >= 1
    assert metrics.background_jobs_active.get(task="app.services.tasks.dispatch_email") == 0


def test_component_health_gauge():
    from app.core.observability import metrics

    metrics.set_component_health("database", True)
    metrics.set_component_health("redis", False)
    assert metrics.health_component.get(component="database") == 1
    assert metrics.health_component.get(component="redis") == 0


# ── Deployment ──────────────────────────────────────────────────────────────


def test_deployment_metadata_shape():
    from app.core.observability.deployment import deployment_metadata

    meta = deployment_metadata()
    assert set(meta) == {"commit", "build_id", "version", "environment"}
    assert meta["environment"] in ("test", "testing")
    assert meta["commit"]


def test_register_deployment_sets_gauges():
    from app.core.observability import metrics
    from app.core.observability.deployment import register_deployment

    meta = register_deployment("starting")
    assert metrics.deployment_info.get(
        commit=meta["commit"], build_id=meta["build_id"],
        version=meta["version"], environment=meta["environment"],
    ) == 1
    assert metrics.deployment_timestamp_seconds.get() > 0


# ── Resource usage ──────────────────────────────────────────────────────────


def test_resource_sampling_never_raises():
    from app.core.observability.resource_usage import collect_snapshot, refresh_resource_gauges

    snap = collect_snapshot()
    assert set(snap) == {"rss_bytes", "vms_bytes", "cpu_seconds", "threads",
                         "open_fds", "start_time", "load_1", "load_5", "load_15"}
    assert snap["threads"] is not None and snap["threads"] > 0
    assert snap["start_time"] is not None
    # On dev boxes (Windows) psutil//proc may be absent — must not raise.
    refresh_resource_gauges()


# ── Alert engine ────────────────────────────────────────────────────────────


def test_alert_manager_fire_and_resolve():
    from app.core.observability import metrics
    from app.core.observability.alerting import AlertManager, AlertRule

    calls = []

    class CapturingNotifier:
        def notify(self, record):
            calls.append((record.status, record.rule))

    mgr = AlertManager(
        rules=[
            AlertRule(
                name="test_db_down",
                description="db down",
                severity="critical",
                evaluate=lambda: metrics.db_available.get() == 0,
                message="db unreachable",
            )
        ],
        notifiers=[CapturingNotifier()],
    )

    metrics.db_available.set(0)
    events = mgr.evaluate_all()
    assert any(e.status == "firing" and e.rule == "test_db_down" for e in events)
    assert mgr.firing()
    assert metrics.alert_active.get(rule="test_db_down") == 1

    metrics.db_available.set(1)
    events = mgr.evaluate_all()
    assert any(e.status == "resolved" and e.rule == "test_db_down" for e in events)
    assert not mgr.firing()
    assert metrics.alert_active.get(rule="test_db_down") == 0
    assert ("firing", "test_db_down") in calls
    assert ("resolved", "test_db_down") in calls


def test_alert_delta_counters():
    from app.core.observability import metrics
    from app.core.observability.alerting import AlertManager

    mgr = AlertManager(rules=[])  # no rules — only delta math
    mgr._prime_baseline()
    metrics.redis_errors_total.inc(op="ping")
    metrics.redis_errors_total.inc(op="ping")
    assert mgr.sum_delta_counter("hl_redis_errors_total") == 2
    assert mgr.sum_delta_counter("hl_redis_errors_total") == 0  # next window empty


def test_default_alert_rules_present():
    from app.core.observability.alerting import default_alert_rules

    rules = default_alert_rules()
    names = {r.name for r in rules}
    assert "database_unreachable" in names
    assert "redis_unreachable" in names
    assert "auth_failure_burst" in names
    assert "http_error_rate_high" in names
    assert "background_job_failures" in names
    for rule in rules:
        assert rule.severity in ("info", "warning", "critical")


# ── Celery signals ──────────────────────────────────────────────────────────


def test_celery_signal_hooks_installed():
    import app.core.observability.celery_signals as cs

    cs.install_celery_observability()
    cs.install_celery_observability()  # idempotent
    assert cs._connected is True


def test_celery_task_events_recorded():
    from app.core.observability import metrics
    from app.core.observability.celery_signals import _finish_task, _on_task_prerun

    _on_task_prerun(task="app.services.tasks.dispatch_email", task_id="task-phase24-1")
    assert metrics.background_jobs_active.get(task="app.services.tasks.dispatch_email") == 1
    _finish_task("task-phase24-1", "succeeded")
    assert metrics.background_jobs_active.get(task="app.services.tasks.dispatch_email") == 0
    assert metrics.background_jobs_total.get(
        task="app.services.tasks.dispatch_email", event="succeeded"
    ) >= 1


def test_celery_beat_schedule_has_observability_tasks():
    from app.core.celery_app import celery_app

    schedule = celery_app.conf.beat_schedule
    assert "observe.evaluate-alerts" in schedule
    assert "observe.sample-resource-usage" in schedule
    assert schedule["observe.evaluate-alerts"]["task"] == "app.core.tasks.evaluate_alert_rules"


# ── HTTP routes / middleware ────────────────────────────────────────────────


@pytest.fixture(scope="module")
def app_client():
    from fastapi.testclient import TestClient

    from app.main import app

    app.dependency_overrides = {}
    # TestClient used WITHOUT a ``with`` block so the lifespan (DB connect,
    # PostGIS enable) does not run — mirrors the other API test modules.
    return TestClient(app)


def test_metrics_endpoint_returns_prometheus_text(app_client):
    from app.core.observability import metrics

    metrics.record_http_request("GET", "/api/v1/health", 200, 0.01)
    response = app_client.get("/metrics")
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/plain")
    assert "# TYPE hl_http_requests_total counter" in response.text
    assert "hl_http_request_duration_seconds_bucket" in response.text


def test_metrics_endpoint_token_protection(monkeypatch):
    from fastapi.testclient import TestClient

    monkeypatch.setattr("app.core.config.settings.METRICS_TOKEN", "sekret-token")
    from app.main import app

    client = TestClient(app)
    assert client.get("/metrics").status_code in (401, 403)
    assert client.get(
        "/metrics", headers={"Authorization": "Bearer wrong"}
    ).status_code in (401, 403)
    assert client.get(
        "/metrics", headers={"Authorization": "Bearer sekret-token"}
    ).status_code == 200
    monkeypatch.undo()


def test_metrics_middleware_records_requests(app_client):
    from app.core.observability import metrics

    before = metrics.http_requests_total.get(method="GET", path="/metrics")
    app_client.get("/metrics")
    app_client.get("/metrics")
    after = metrics.http_requests_total.get(method="GET", path="/metrics")
    assert after > before


def test_access_log_query_scrubbing():
    from starlette.requests import Request

    from app.core.observability.access_log import _safe_query_params

    scope = {
        "type": "http",
        "method": "GET",
        "path": "/api/v1/search",
        "query_string": b"otp=482913&q=phones&access_token=abc123&utm=share",
        "headers": [],
        "client": ("1.2.3.4", 1234),
        "scheme": "http",
        "server": ("test", 80),
    }
    params = _safe_query_params(Request(scope))
    assert params["otp"] == "[REDACTED]"
    assert params["access_token"] == "[REDACTED]"
    assert params["q"] == "phones"
    assert params["utm"] == "share"


def test_admin_observability_overview_requires_admin(app_client):
    response = app_client.get("/admin/observability/overview")
    assert response.status_code in (401, 403)


def test_observability_admin_routes_registered():
    from app.main import app

    for name in ("observability_overview", "observability_alerts"):
        assert app.url_path_for(name)


# ── Config / health ─────────────────────────────────────────────────────────


def test_observability_settings_exist():
    from app.core.config import Settings

    s = Settings(_env_file=None, ENVIRONMENT="test")
    assert hasattr(s, "LOG_SERVICE_NAME")
    assert hasattr(s, "METRICS_TOKEN")
    assert hasattr(s, "ALERT_WEBHOOK_URL")
    assert hasattr(s, "LOG_EXTRA_FIELDS")


def test_health_router_still_exposes_health_and_ready():
    from app.core.health import router

    paths = {r.path for r in router.routes}
    assert "/health" in paths
    assert "/ready" in paths