"""Threshold-based alert engine (firing/resolved lifecycle + notifiers).

An :class:`AlertRule` is a named condition evaluated over the metric
registry. The :class:`AlertManager`:

* primes baseline counter values once (no false-positive bursts on boot),
* tracks per-rule delta windows between evaluations,
* moves rules FIRING -> RESOLVED and records both events,
* keeps a bounded ring-buffer history for the admin endpoint,
* mirrors state into ``hl_alert_active`` / ``hl_alerts_fired_total``,
* notifies via pluggable notifiers (log / webhook / email).

Alert evaluation runs from the ``app.core.tasks.evaluate_alert_rules``
Celery beat task (see ``app/core/celery_app.py``) and can also be
triggered on demand.
"""

from __future__ import annotations

import logging
from collections import deque
from dataclasses import dataclass
from time import time
from typing import Callable, Dict, List, Optional, Sequence, Tuple

from app.core.observability import metrics
from app.core.observability.registry import get_registry

logger = logging.getLogger("app.observability.alert")


# ── Records ─────────────────────────────────────────────────────────────────
@dataclass
class AlertRecord:
    rule: str
    severity: str
    status: str               # firing | resolved
    message: str
    first_seen: float
    last_seen: float

    def to_dict(self) -> dict:
        return {
            "rule": self.rule,
            "severity": self.severity,
            "status": self.status,
            "message": self.message,
            "first_seen": self.first_seen,
            "last_seen": self.last_seen,
        }


@dataclass
class AlertRule:
    name: str
    description: str
    severity: str                        # info | warning | critical
    evaluate: Callable[[], bool]         # True -> condition is failing
    message: Optional[str] = None

    def __post_init__(self) -> None:
        if self.severity not in ("info", "warning", "critical"):
            raise ValueError(f"Bad severity {self.severity!r} for rule {self.name!r}")


# ── Notifiers ───────────────────────────────────────────────────────────────
class BaseNotifier:
    def notify(self, record: AlertRecord) -> None:  # pragma: no cover - interface
        raise NotImplementedError


class LogNotifier(BaseNotifier):
    """Emit the alert as a structured log line (always the last resort)."""

    def notify(self, record: AlertRecord) -> None:
        level = {
            "critical": logging.CRITICAL,
            "warning": logging.WARNING,
            "info": logging.INFO,
        }[record.severity]
        logger.log(
            level,
            "ALERT [%s] %s — %s",
            record.status.upper(),
            record.rule,
            record.message,
            extra={"event": "alert", "alert_rule": record.rule},
        )


class WebhookNotifier(BaseNotifier):
    """POST the alert to a configured webhook (Prometheus Alertmanager etc.)."""

    def __init__(self, url: str, timeout: float = 5.0) -> None:
        self.url = url
        self.timeout = timeout

    def notify(self, record: AlertRecord) -> None:
        if not self.url:
            return
        try:
            import httpx

            httpx.post(
                self.url,
                json={
                    "title": f"[{record.status.upper()}] {record.rule}",
                    "severity": record.severity,
                    "status": record.status,
                    "message": record.message,
                    "rule": record.rule,
                    "first_seen": record.first_seen,
                    "last_seen": record.last_seen,
                },
                timeout=self.timeout,
            )
        except Exception as exc:  # noqa: BLE001 — notifications never break alerting
            logger.warning("Webhook notifier failed for %s: %s", record.rule, exc)


# ── Alert manager ───────────────────────────────────────────────────────────
class AlertManager:
    def __init__(
        self,
        rules: Sequence[AlertRule] = (),
        notifiers: Sequence[BaseNotifier] = (),
    ) -> None:
        self.rules: List[AlertRule] = list(rules)
        self.notifiers: List[BaseNotifier] = list(notifiers)
        self._history: deque = deque(maxlen=500)
        self._firing: Dict[str, AlertRecord] = {}
        self._last_counts: Dict[Tuple[str, Tuple[str, ...]], float] = {}
        self._primed = False
        self._registry = get_registry()

    # ── setup ──────────────────────────────────────────────────────────────
    def add_rule(self, rule: AlertRule) -> None:
        self.rules.append(rule)

    def set_notifiers(self, notifiers: Sequence[BaseNotifier]) -> None:
        self.notifiers = list(notifiers)

    # ── delta arithmetic ───────────────────────────────────────────────────
    def _record_snapshot(self, metric_name: str, label_values: Tuple[str, ...], value: float) -> None:
        self._last_counts[(metric_name, label_values)] = value

    def _prime_baseline(self) -> None:
        """Baseline every counter so the first evaluation sees a zero delta."""
        for name in self._registry.metric_names():
            metric = self._registry.get(name)
            if metric is None or metric.typ != "counter":
                continue
            for label_values, value in metric.items():
                self._record_snapshot(name, label_values, value)

    def delta_counter(self, name: str, **labels: str) -> float:
        """Delta of one counter label-combo since the last evaluation."""
        metric = self._registry.get(name)
        if metric is None:
            return 0.0
        try:
            label_values = metric._labels_tuple(dict(labels))
        except Exception:  # noqa: BLE001
            label_values = tuple(labels.get(n, "") for n in metric.labelnames)
        current = metric.get(**labels)
        previous = self._last_counts.get((name, label_values), current)
        self._record_snapshot(name, label_values, current)
        return current - previous

    def sum_delta_counter(self, name: str) -> float:
        """Delta summed across every label-combo of a counter."""
        metric = self._registry.get(name)
        if metric is None:
            return 0.0
        total = 0.0
        for label_values, value in metric.items():
            previous = self._last_counts.get((name, label_values), value)
            self._record_snapshot(name, label_values, value)
            total += value - previous
        return total

    def task_failures_since_last(self) -> float:
        """Delta of background jobs that failed (label event == 'failed')."""
        metric = self._registry.get("hl_background_jobs_total")
        if metric is None:
            return 0.0
        total = 0.0
        for label_values, value in metric.items():
            if len(label_values) >= 2 and label_values[1] == "failed":
                previous = self._last_counts.get(("hl_background_jobs_total", label_values), value)
                self._record_snapshot("hl_background_jobs_total", label_values, value)
                total += value - previous
        return total

    def evaluate_all(self) -> List[AlertRecord]:
        """Evaluate every rule; return only NEW records (fires and resolves)."""
        if not self._primed:
            self._prime_baseline()
            self._primed = True

        results: List[AlertRecord] = []
        now = time()
        for rule in self.rules:
            try:
                failing = bool(rule.evaluate())
            except Exception as exc:  # noqa: BLE001 — one bad rule must not stop the sweep
                logger.warning("Alert rule %s raised during evaluation: %s", rule.name, exc)
                continue

            if failing:
                record = self._firing.get(rule.name)
                if record is None:
                    record = AlertRecord(
                        rule=rule.name,
                        severity=rule.severity,
                        status="firing",
                        message=rule.message or rule.description,
                        first_seen=now,
                        last_seen=now,
                    )
                    self._firing[rule.name] = record
                    self._history.append(record)
                    metrics.alerts_fired_total.inc(rule=rule.name, severity=rule.severity)
                    metrics.alert_active.set(1, rule=rule.name)
                    results.append(record)
                    self._notify(record)
                else:
                    record.last_seen = now
            else:
                record = self._firing.pop(rule.name, None)
                if record is not None:
                    resolved = AlertRecord(
                        rule=record.rule,
                        severity=record.severity,
                        status="resolved",
                        message=record.message,
                        first_seen=record.first_seen,
                        last_seen=now,
                    )
                    self._history.append(resolved)
                    metrics.alert_active.set(0, rule=record.rule)
                    results.append(resolved)
                    self._notify(resolved)
        return results

    def _notify(self, record: AlertRecord) -> None:
        for notifier in self.notifiers:
            try:
                notifier.notify(record)
            except Exception as exc:  # noqa: BLE001
                logger.warning("Notifier error for alert %s: %s", record.rule, exc)

    # ── introspection ──────────────────────────────────────────────────────
    def firing(self) -> List[AlertRecord]:
        return list(self._firing.values())

    def snapshot(self) -> List[dict]:
        return [r.to_dict() for r in self.firing()]

    def history(self, limit: int = 100) -> List[dict]:
        return [r.to_dict() for r in list(self._history)[-limit:]]


# ── Default rules ───────────────────────────────────────────────────────────
def default_alert_rules() -> List[AlertRule]:
    """The shipped rule set — every one is threshold-based on real metrics."""

    def _db_down() -> bool:
        return metrics.db_available.get() == 0

    def _redis_down() -> bool:
        return metrics.redis_available.get() == 0

    def _storage_down() -> bool:
        return metrics.storage_available.get() == 0

    def _s3_burst() -> bool:
        return manager().sum_delta_counter("hl_storage_failures_total") >= 10

    def _auth_burst() -> bool:
        return manager().sum_delta_counter("hl_auth_failures_total") >= 20

    def _http_error_rate() -> bool:
        requests = manager().sum_delta_counter("hl_http_requests_total")
        errors = manager().sum_delta_counter("hl_http_errors_total")
        if requests < 50:
            return False
        return (errors / requests) > 0.10

    def _latency_high() -> bool:
        return metrics.http_request_duration_seconds.average() > 2.0

    def _redis_error_burst() -> bool:
        return manager().sum_delta_counter("hl_redis_errors_total") >= 20

    def _db_error_burst() -> bool:
        return manager().sum_delta_counter("hl_db_errors_total") >= 20

    def _bg_failures() -> bool:
        return manager().task_failures_since_last() > 0

    return [
        AlertRule(
            name="database_unreachable",
            description="PostgreSQL is not reachable from this instance.",
            severity="critical",
            evaluate=_db_down,
            message="Database connectivity check failed",
        ),
        AlertRule(
            name="redis_unreachable",
            description="Redis is not reachable; caching and queues are degraded.",
            severity="critical",
            evaluate=_redis_down,
            message="Redis connectivity check failed",
        ),
        AlertRule(
            name="storage_unavailable",
            description="Object storage (S3) is not reachable.",
            severity="warning",
            evaluate=_storage_down,
            message="Object storage availability check failed",
        ),
        AlertRule(
            name="storage_failure_burst",
            description="More than 10 storage failures since the last evaluation.",
            severity="warning",
            evaluate=_s3_burst,
            message="Storage operation failure burst",
        ),
        AlertRule(
            name="auth_failure_burst",
            description="More than 20 failed authentication attempts per interval — possible brute force.",
            severity="critical",
            evaluate=_auth_burst,
            message="Authentication failure burst (possible credential stuffing)",
        ),
        AlertRule(
            name="http_error_rate_high",
            description="HTTP error rate above 10% over the last interval (>= 50 requests).",
            severity="warning",
            evaluate=_http_error_rate,
            message="HTTP error rate above 10%",
        ),
        AlertRule(
            name="http_latency_high",
            description="Average request latency above 2s since boot.",
            severity="warning",
            evaluate=_latency_high,
            message="Average request latency above 2 seconds",
        ),
        AlertRule(
            name="background_job_failures",
            description="One or more background jobs failed since the last evaluation.",
            severity="warning",
            evaluate=_bg_failures,
            message="Background job failures detected",
        ),
        AlertRule(
            name="redis_error_burst",
            description="More than 20 Redis errors since the last evaluation.",
            severity="warning",
            evaluate=_redis_error_burst,
            message="Redis error burst",
        ),
        AlertRule(
            name="db_error_burst",
            description="More than 20 database errors since the last evaluation.",
            severity="warning",
            evaluate=_db_error_burst,
            message="Database error burst",
        ),
    ]


_manager: Optional[AlertManager] = None


def manager() -> AlertManager:
    """Return the process-wide alert manager (created once, lazily)."""
    global _manager
    if _manager is None:
        _manager = AlertManager(rules=default_alert_rules(), notifiers=[LogNotifier()])
        logger.info("Alert manager initialised with %d rules", len(_manager.rules))
    return _manager


def evaluate_alerts() -> List[AlertRecord]:
    """Evaluate all rules and return new records (used by the beat task)."""
    return manager().evaluate_all()