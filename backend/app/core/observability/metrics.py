"""Standard metric instances + instrumentation helpers for the platform.

Every counter/gauge/histogram defined here covers one of the tracked
observability signals:

* API errors / request latency       ``hl_http_*``
* database errors / availability     ``hl_db_*``
* Redis errors / availability        ``hl_redis_*``
* S3 / storage failures              ``hl_storage_*``
* authentication failures            ``hl_auth_*``
* background jobs (Celery)           ``hl_background_jobs_*``
* deployment status                  ``hl_deployment_*``
* resource usage                     ``hl_process_*`` / ``hl_system_*``
* application health                 ``hl_health*``
* alert lifecycle                    ``hl_alert*``
"""

from __future__ import annotations

import re

from app.core.observability.registry import (
    Registry,
    counter,
    gauge,
    get_registry,
    histogram,
)

# All metric instances register themselves into this shared registry.
registry: Registry = get_registry()

# ── HTTP request / latency / errors ─────────────────────────────────────────
http_requests_total = counter(
    "hl_http_requests_total",
    "Total HTTP requests processed.",
    ["method", "path"],
)
http_request_duration_seconds = histogram(
    "hl_http_request_duration_seconds",
    "HTTP request latency in seconds.",
    ["method", "path"],
)
http_errors_total = counter(
    "hl_http_errors_total",
    "HTTP responses with status >= 400.",
    ["method", "path", "status"],
)
http_5xx_total = counter(
    "hl_http_5xx_total",
    "HTTP 5xx responses (server-side faults).",
    ["method", "path"],
)
rate_limit_rejections_total = counter(
    "hl_rate_limit_rejections_total",
    "Requests rejected by the rate limiter (429).",
    ["method", "path"],
)

# ── Database ────────────────────────────────────────────────────────────────
db_errors_total = counter(
    "hl_db_errors_total",
    "Database errors by kind (connect|statement|integrity|unknown).",
    ["kind"],
)
db_available = gauge(
    "hl_db_available",
    "1 when the database is reachable, 0 otherwise.",
)

# ── Redis ───────────────────────────────────────────────────────────────────
redis_errors_total = counter(
    "hl_redis_errors_total",
    "Redis command/connection errors by operation.",
    ["op"],
)
redis_available = gauge(
    "hl_redis_available",
    "1 when Redis is reachable, 0 otherwise.",
)

# ── Storage (S3 / local / cloudinary) ───────────────────────────────────────
storage_operations_total = counter(
    "hl_storage_operations_total",
    "Storage operations attempted by operator and outcome.",
    ["op", "provider", "status"],
)
storage_failures_total = counter(
    "hl_storage_failures_total",
    "Storage operation failures by operator.",
    ["op", "provider"],
)
storage_available = gauge(
    "hl_storage_available",
    "1 when the object-storage provider is reachable, 0 otherwise.",
)
storage_provider = gauge(
    "hl_storage_provider",
    "Active storage provider (1 for the configured provider).",
    ["provider"],
)

# ── Authentication ──────────────────────────────────────────────────────────
auth_attempts_total = counter(
    "hl_auth_attempts_total",
    "Authentication attempts by channel.",
    ["channel"],
)
auth_failures_total = counter(
    "hl_auth_failures_total",
    "Authentication failures by channel and reason.",
    ["channel", "reason"],
)
otp_store_available = gauge(
    "hl_otp_store_available",
    "1 when the OTP store backend is reachable, 0 otherwise.",
)

# ── Background jobs (Celery) ────────────────────────────────────────────────
background_jobs_total = counter(
    "hl_background_jobs_total",
    "Background job lifecycle events (started|succeeded|failed|retried).",
    ["task", "event"],
)
background_jobs_active = gauge(
    "hl_background_jobs_active",
    "Background jobs currently executing, by task.",
    ["task"],
)
background_job_duration_seconds = histogram(
    "hl_background_job_duration_seconds",
    "Background job wall-clock duration in seconds.",
    ["task", "event"],
)
background_queue_length = gauge(
    "hl_background_queue_length",
    "Undelivered Celery messages observed via control/broadcast.",
    ["queue"],
)

# ── Deployment ──────────────────────────────────────────────────────────────
deployment_info = gauge(
    "hl_deployment_info",
    "Build/deploy identity (1 for the live deployment).",
    ["commit", "build_id", "version", "environment"],
)
deployment_timestamp_seconds = gauge(
    "hl_deployment_timestamp_seconds",
    "Unix time the current deployment started.",
)
deployments_total = counter(
    "hl_deployments_total",
    "Deployments by result (starting|success|failure).",
    ["environment", "result"],
)

# ── Resource usage ──────────────────────────────────────────────────────────
process_rss_bytes = gauge("hl_process_rss_bytes", "Resident set size of the process.")
process_virtual_memory_bytes = gauge(
    "hl_process_virtual_memory_bytes", "Virtual memory size of the process."
)
process_cpu_seconds_total = gauge(
    "hl_process_cpu_seconds_total", "Cumulative CPU time of the process."
)
process_threads = gauge("hl_process_threads", "Number of threads in the process.")
process_open_fds = gauge("hl_process_open_fds", "Open file descriptors of the process.")
process_start_time_seconds = gauge(
    "hl_process_start_time_seconds", "Start time of the process (unix seconds)."
)
system_load_1 = gauge("hl_system_load_1", "System 1-minute load average.")
system_load_5 = gauge("hl_system_load_5", "System 5-minute load average.")
system_load_15 = gauge("hl_system_load_15", "System 15-minute load average.")

# ── Health / readiness ──────────────────────────────────────────────────────
health_component = gauge(
    "hl_health_component",
    "Component health as last observed by the readiness probe (1 ok / 0 bad).",
    ["component"],
)
health_checks_total = counter(
    "hl_health_checks_total",
    "Readiness probe evaluations.",
    ["result"],
)

# ── Alerts ──────────────────────────────────────────────────────────────────
alerts_fired_total = counter(
    "hl_alerts_fired_total",
    "Alert rules that entered the FIRING state (deduplicated per firing).",
    ["rule", "severity"],
)
alert_active = gauge(
    "hl_alert_active",
    "1 while an alert rule is firing, 0 when resolved.",
    ["rule"],
)


# ── Cardinality control ─────────────────────────────────────────────────────
_UUID_PATTERN = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
)


def normalize_path(path: str) -> str:
    """Replace per-entity segments with a placeholder to bound label cardinality.

    ``/api/v1/shops/42``   -> ``/api/v1/shops/{id}``
    ``/api/v1/auth/otp/…``  (uuid) -> ``/api/v1/...{id}``
    """
    parts = []
    for segment in path.split("/"):
        if segment.isdigit() or _UUID_PATTERN.match(segment):
            segment = "{id}"
        parts.append(segment)
    return "/".join(parts)


# ── HTTP instrumentation ────────────────────────────────────────────────────
def record_http_request(method: str, path: str, status: int, duration_seconds: float) -> None:
    """Record one completed HTTP request (count, latency, error counters)."""
    norm_path = normalize_path(path)
    method = method.upper()
    http_requests_total.inc(method=method, path=norm_path)
    http_request_duration_seconds.observe(max(0.0, float(duration_seconds)), method=method, path=norm_path)
    if int(status) >= 400:
        http_errors_total.inc(method=method, path=norm_path, status=str(status))
    if int(status) >= 500:
        http_5xx_total.inc(method=method, path=norm_path)
    if int(status) == 429:
        rate_limit_rejections_total.inc(method=method, path=norm_path)


def record_rate_limit_rejection(method: str, path: str) -> None:
    rate_limit_rejections_total.inc(method=method.upper(), path=normalize_path(path))


# ── Database instrumentation ────────────────────────────────────────────────
def record_db_error(kind: str = "unknown") -> None:
    db_errors_total.inc(kind=kind)


def set_db_available(ok: bool) -> None:
    db_available.set(1 if ok else 0)


# ── Redis instrumentation ───────────────────────────────────────────────────
def record_redis_error(op: str = "command") -> None:
    redis_errors_total.inc(op=op)


def set_redis_available(ok: bool) -> None:
    redis_available.set(1 if ok else 0)


# ── Storage instrumentation ─────────────────────────────────────────────────
def record_storage_operation(op: str, provider: str, ok: bool) -> None:
    storage_operations_total.inc(op=op, provider=provider, status="ok" if ok else "error")
    if not ok:
        storage_failures_total.inc(op=op, provider=provider)


def set_storage_available(ok: bool) -> None:
    storage_available.set(1 if ok else 0)


# ── Auth instrumentation ────────────────────────────────────────────────────
def record_auth_result(channel: str, ok: bool, reason: str = "success") -> None:
    """Record one authentication outcome (success or failure with a reason)."""
    auth_attempts_total.inc(channel=channel)
    if not ok:
        auth_failures_total.inc(channel=channel, reason=reason or "unknown")


def set_otp_store_available(ok: bool) -> None:
    otp_store_available.set(1 if ok else 0)


# ── Background jobs instrumentation ─────────────────────────────────────────
def record_background_job(task: str, event: str) -> None:
    """Record a background-job lifecycle event (started|succeeded|failed|retried)."""
    background_jobs_total.inc(task=task, event=event)


def set_background_job_active(task: str, active: bool) -> None:
    background_jobs_active.set(1 if active else 0, task=task)


# ── Health / deployment instrumentation ─────────────────────────────────────
def set_component_health(component: str, ok: bool) -> None:
    health_component.set(1 if ok else 0, component=component)


# ── Phase 57 — Observability: DB latency / cache hit-miss / search latency ──
db_query_duration_seconds = histogram(
    "hl_db_query_duration_seconds",
    "Database query latency in seconds by operation kind.",
    ["kind"],                       # select | insert | update | delete | other
)

cache_operations_total = counter(
    "hl_cache_operations_total",
    "Cache operations by result (hit|miss|error).",
    ["op", "result"],               # op: get|set|delete  result: hit|miss|error
)

cache_hit_ratio = gauge(
    "hl_cache_hit_ratio",
    "Rolling cache hit ratio (0.0–1.0). Updated by the cache layer.",
)

search_duration_seconds = histogram(
    "hl_search_duration_seconds",
    "Search request latency in seconds by search kind.",
    ["kind"],                       # products | suggestions | barcode | nearby
)

search_results_total = counter(
    "hl_search_requests_total",
    "Search requests by kind and outcome (ok|empty|error).",
    ["kind", "outcome"],
)


def record_db_query(kind: str, duration_seconds: float) -> None:
    """Record one database query latency observation."""
    db_query_duration_seconds.observe(max(0.0, float(duration_seconds)), kind=kind)


def record_cache_operation(op: str, result: str) -> None:
    """Record a cache get/set/delete outcome (hit|miss|error)."""
    cache_operations_total.inc(op=op, result=result)


def update_cache_hit_ratio() -> None:
    """Recompute the rolling cache hit ratio from the operation counters."""
    try:
        hits = cache_operations_total.get(op="get", result="hit")
        misses = cache_operations_total.get(op="get", result="miss")
        total = hits + misses
        if total > 0:
            cache_hit_ratio.set(hits / total)
    except Exception:  # noqa: BLE001 — telemetry must never break the caller
        pass


def record_search_request(kind: str, duration_seconds: float, outcome: str = "ok") -> None:
    """Record one search request (latency + outcome)."""
    search_duration_seconds.observe(max(0.0, float(duration_seconds)), kind=kind)
    search_results_total.inc(kind=kind, outcome=outcome)