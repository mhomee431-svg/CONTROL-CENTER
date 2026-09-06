"""Observability HTTP routes (Phase 24).

* ``GET /metrics``            — Prometheus text exposition of every metric.
                               Optional bearer-token protection
                               (``METRICS_TOKEN``) for non-production scraping.
* ``GET /admin/observability/overview`` — admin-dashboard JSON snapshot
                               (metric + alert state) for at-a-glance checks.
* ``GET /admin/observability/alerts``   — current firing alerts + history.

``/metrics`` lives OUTSIDE the ``/api/v1`` prefix and is excluded from the
auth scopes so infra probes can scrape it. It stays mounted even for
unauthenticated scrapes unless ``METRICS_TOKEN`` is set.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query, Request
from fastapi.responses import PlainTextResponse

from app.core.config import settings
from app.core.dependencies import require_admin_permission
from app.core.observability import resource_usage
from app.core.observability.alerting import manager
from app.core.observability.registry import get_registry
from app.core.responses import success_response

router = APIRouter(tags=["observability"])

# Metrics are pre-registered at import-time by ``app.core.observability.metrics``.
_refresh_registry = get_registry()


@router.get(
    "/metrics",
    response_class=PlainTextResponse,
    include_in_schema=False,
)
async def metrics_endpoint(request: Request):
    """Expose Prometheus text metrics.

    * Auth: when ``METRICS_TOKEN`` is configured the caller must present it
      via ``Authorization: Bearer <token>``; otherwise the endpoint is open
      (scrape-only — no sensitive data is ever exposed).
    * Refresh: resource gauges are sampled on every scrape (cheap, cached).
    """
    if settings.METRICS_TOKEN:
        auth_header = request.headers.get("authorization", "")
        provided = auth_header.removeprefix("Bearer ").strip() if auth_header else ""
        if provided != settings.METRICS_TOKEN:
            from app.core.exceptions import UnauthorizedError

            raise UnauthorizedError("Invalid or missing metrics token")
    # Sample process/OS resources on-demand so the scrape is always fresh.
    try:
        resource_usage.refresh_resource_gauges()
    except Exception:  # noqa: BLE001 — metrics scraping must never 5xx
        pass
    body = _refresh_registry.render()
    return PlainTextResponse(
        content=body,
        media_type="text/plain; version=0.0.4",
    )


@router.get("/admin/observability/overview")
async def observability_overview(
    _=Depends(require_admin_permission("analytics", "read")),
):
    """Aggregate JSON snapshot: component health + headline metrics."""
    items = {}
    for name in _refresh_registry.metric_names():
        metric = _refresh_registry.get(name)
        if metric is None:
            continue
        # Only report gauges/counters with at least one set label-combo so
        # the overview stays compact and meaningful.
        if metric.typ == "histogram":
            continue
        if metric.typ in ("counter", "gauge") and metric.items():
            items[name] = {labels: value for labels, value in metric.items()}
    try:
        resource_usage.refresh_resource_gauges()
    except Exception:  # noqa: BLE001
        pass
    return success_response(
        data={
            "environment": settings.ENVIRONMENT,
            "version": settings.APP_VERSION,
            "metrics": items,
            "alerts": {
                "firing": manager().snapshot(),
                "history": manager().history(limit=50),
            },
        },
        message="Observability overview",
    )


@router.get("/admin/observability/alerts")
async def observability_alerts(
    limit: int = Query(100, ge=1, le=500),
    _=Depends(require_admin_permission("analytics", "read")),
):
    """Current firing alerts and the bounded alert history."""
    return success_response(
        data={
            "firing": manager().snapshot(),
            "history": manager().history(limit=limit),
        },
        message="Alerts",
    )