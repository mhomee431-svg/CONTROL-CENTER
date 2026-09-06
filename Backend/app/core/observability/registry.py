"""Thread-safe Prometheus text-format metric primitives (standard library only).

This module deliberately ships **no** third-party dependency (no
``prometheus-client``) so the metrics pipeline is identical on the local
dev box, in CI, and inside the production image — there is no wheel or
Python-version risk to manage. The emitted format is the standard
Prometheus text exposition format 0.0.4, so any Prometheus / OpenMetrics
scraper, the CloudWatch agent's ``prometheus`` source, or DataDog's
``prometheus`` check can consume ``GET /metrics`` directly.

Supported metric types:

* :class:`Counter`   — monotonically increasing counters (requests, errors)
* :class:`Gauge`     — snapshots that go up and down (active jobs, memory)
* :class:`Histogram` — sampled observations into cumulative buckets
                       (latencies); exposes ``_bucket`` / ``_sum`` / ``_count``
"""

from __future__ import annotations

import re
import threading
from typing import Any, Dict, List, Optional, Sequence, Tuple

_METRIC_NAME_RE = re.compile(r"^[a-zA-Z_:][a-zA-Z0-9_:]*$")

# Prometheus default histogram buckets (seconds-appropriate for HTTP latency).
DEFAULT_BUCKETS: Tuple[float, ...] = (
    0.005, 0.01, 0.025, 0.05, 0.075, 0.1, 0.25, 0.5, 0.75,
    1.0, 2.5, 5.0, 7.5, 10.0,
)


def _escape_label_value(value: Any) -> str:
    """Escape a label value per the Prometheus text format (\\, \", \n)."""
    return (
        str(value)
        .replace("\\", "\\\\")
        .replace("\n", "\\n")
        .replace('"', '\\"')
    )


def _format_value(value: float) -> str:
    if float(value).is_integer():
        return str(int(value))
    return repr(float(value))


class Metric:
    """Base class for all metric types (name validation + label bookkeeping)."""

    def __init__(
        self,
        name: str,
        help_text: str,
        labelnames: Sequence[str] = (),
        registry: Optional["Registry"] = None,
        typ: str = "gauge",
    ) -> None:
        if not _METRIC_NAME_RE.match(name):
            raise ValueError(f"Invalid metric name: {name!r}")
        self.name = name
        self.help_text = help_text
        self.labelnames: Tuple[str, ...] = tuple(labelnames)
        self.typ = typ
        self._values: Dict[Tuple[str, ...], float] = {}
        self._lock = threading.Lock()
        if registry is not None:
            registry.register(self)

    # ── label handling ─────────────────────────────────────────────────────
    def _labels_tuple(self, labelvalues: Dict[str, Any]) -> Tuple[str, ...]:
        for key in labelvalues:
            if key not in self.labelnames:
                raise KeyError(
                    f"Unexpected label {key!r} for metric {self.name} "
                    f"(allowed: {self.labelnames})"
                )
        return tuple(
            str(labelvalues.get(name, "")) for name in self.labelnames
        )

    # ── accessors ──────────────────────────────────────────────────────────
    def get(self, **labelvalues: Any) -> float:
        key = self._labels_tuple(labelvalues)
        with self._lock:
            return float(self._values.get(key, 0.0))

    def items(self) -> List[Tuple[Tuple[str, ...], float]]:
        """Return ``(label-values-tuple, value)`` pairs (used by alert deltas)."""
        with self._lock:
            return list(self._values.items())

    def _render_header(self) -> List[str]:
        return [
            f"# HELP {self.name} {self.help_text}".strip(),
            f"# TYPE {self.name} {self.typ}",
        ]

    def _render_samples(self) -> List[str]:
        raise NotImplementedError

    def render(self) -> str:
        with self._lock:
            samples = self._render_samples()
        if not samples:
            return ""
        return "\n".join(self._render_header() + samples) + "\n"


class Counter(Metric):
    """Monotonically increasing counter that resets on process restart."""

    def __init__(
        self,
        name: str,
        help_text: str,
        labelnames: Sequence[str] = (),
        registry: Optional["Registry"] = None,
    ) -> None:
        super().__init__(name, help_text, labelnames, registry, typ="counter")

    def inc(self, amount: float = 1, **labelvalues: Any) -> None:
        key = self._labels_tuple(labelvalues)
        with self._lock:
            self._values[key] = self._values.get(key, 0.0) + float(amount)

    def _render_samples(self) -> List[str]:
        out = []
        for label_values, value in sorted(self._values.items()):
            labels = ""
            if self.labelnames:
                pairs = ",".join(
                    f'{name}="{_escape_label_value(value)}"'
                    for name, value in zip(self.labelnames, label_values)
                )
                labels = "{" + pairs + "}"
            out.append(f"{self.name}{labels} {_format_value(value)}")
        return out


class Gauge(Metric):
    """Snapshot gauge that can go up and down (or carry info labels)."""

    def __init__(
        self,
        name: str,
        help_text: str,
        labelnames: Sequence[str] = (),
        registry: Optional["Registry"] = None,
    ) -> None:
        super().__init__(name, help_text, labelnames, registry, typ="gauge")

    def set(self, value: float, **labelvalues: Any) -> None:
        key = self._labels_tuple(labelvalues)
        with self._lock:
            self._values[key] = float(value)

    def inc(self, amount: float = 1, **labelvalues: Any) -> None:
        key = self._labels_tuple(labelvalues)
        with self._lock:
            self._values[key] = self._values.get(key, 0.0) + float(amount)

    def dec(self, amount: float = 1, **labelvalues: Any) -> None:
        self.inc(-amount, **labelvalues)

    def _render_samples(self) -> List[str]:
        out = []
        for label_values, value in sorted(self._values.items()):
            labels = ""
            if self.labelnames:
                pairs = ",".join(
                    f'{name}="{_escape_label_value(value)}"'
                    for name, value in zip(self.labelnames, label_values)
                )
                labels = "{" + pairs + "}"
            out.append(f"{self.name}{labels} {_format_value(value)}")
        return out


class _HistogramState:
    __slots__ = ("count", "sum", "buckets")

    def __init__(self, buckets: Tuple[float, ...]) -> None:
        self.count = 0.0
        self.sum = 0.0
        self.buckets = [0.0] * len(buckets)


class Histogram(Metric):
    """Histogram of observations across cumulative Prometheus buckets."""

    def __init__(
        self,
        name: str,
        help_text: str,
        labelnames: Sequence[str] = (),
        buckets: Sequence[float] = DEFAULT_BUCKETS,
        registry: Optional["Registry"] = None,
    ) -> None:
        super().__init__(name, help_text, labelnames, registry, typ="histogram")
        self.buckets: Tuple[float, ...] = tuple(sorted(float(b) for b in buckets))
        # histogram stores richer per-label state than the base class.
        self._hist_values: Dict[Tuple[str, ...], _HistogramState] = {}
        self._lock = threading.Lock()

    def observe(self, value: float, **labelvalues: Any) -> None:
        key = self._labels_tuple(labelvalues)
        with self._lock:
            state = self._hist_values.get(key)
            if state is None:
                state = _HistogramState(self.buckets)
                self._hist_values[key] = state
            state.count += 1
            state.sum += float(value)
            for i, bound in enumerate(self.buckets):
                if float(value) <= bound:
                    state.buckets[i] += 1

    def _counters(self, labelvalues: Dict[str, Any]) -> Tuple[float, float]:
        key = self._labels_tuple(labelvalues)
        with self._lock:
            state = self._hist_values.get(key)
        if state is None:
            return 0.0, 0.0
        return state.count, state.sum

    def count(self, **labelvalues: Any) -> float:
        return self._counters(labelvalues)[0]

    def sum(self, **labelvalues: Any) -> float:
        return self._counters(labelvalues)[1]

    def average(self, **labelvalues: Any) -> float:
        """Mean of the observations for the given labels (0 when empty)."""
        count, total = self._counters(labelvalues)
        return total / count if count else 0.0

    def _render_samples(self) -> List[str]:
        out: List[str] = []
        items = list(self._hist_values.items())
        for label_values, state in sorted(items):
            if self.labelnames:
                pairs = ",".join(
                    f'{name}="{_escape_label_value(value)}"'
                    for name, value in zip(self.labelnames, label_values)
                )
                label_head = "{" + pairs + ","
            else:
                label_head = "{"
            for bound, count in zip(self.buckets, state.buckets):
                out.append(
                    f"{self.name}_bucket{label_head}le=\"{_format_value(bound)}\"}} "
                    f"{_format_value(count)}"
                )
            out.append(
                f"{self.name}_bucket{label_head}le=\"+Inf\"}} "
                f"{_format_value(state.count)}"
            )
            suffix = ""
            if self.labelnames:
                pairs = ",".join(
                    f'{name}="{_escape_label_value(value)}"'
                    for name, value in zip(self.labelnames, label_values)
                )
                suffix = "{" + pairs + "}"
            out.append(f"{self.name}_sum{suffix} {_format_value(state.sum)}")
            out.append(f"{self.name}_count{suffix} {_format_value(state.count)}")
        return out


class Registry:
    """Holds every metric and renders the combined Prometheus text."""

    def __init__(self) -> None:
        self._metrics: List[Metric] = []
        self._by_name: Dict[str, Metric] = {}
        self._lock = threading.Lock()

    def register(self, metric: Metric) -> Metric:
        with self._lock:
            if metric.name in self._by_name:
                raise ValueError(f"Metric already registered: {metric.name}")
            self._metrics.append(metric)
            self._by_name[metric.name] = metric
        return metric

    def get(self, name: str) -> Optional[Metric]:
        with self._lock:
            return self._by_name.get(name)

    def metric_names(self) -> List[str]:
        with self._lock:
            return sorted(self._by_name)

    def render(self) -> str:
        with self._lock:
            metrics = list(self._metrics)
        parts = [m.render() for m in metrics]
        return "\n".join(part for part in parts if part) + "\n"


_default_registry = Registry()


def get_registry() -> Registry:
    return _default_registry


def counter(
    name: str,
    help_text: str,
    labelnames: Sequence[str] = (),
    registry: Optional[Registry] = None,
) -> Counter:
    return Counter(name, help_text, labelnames, registry or _default_registry)


def gauge(
    name: str,
    help_text: str,
    labelnames: Sequence[str] = (),
    registry: Optional[Registry] = None,
) -> Gauge:
    return Gauge(name, help_text, labelnames, registry or _default_registry)


def histogram(
    name: str,
    help_text: str,
    labelnames: Sequence[str] = (),
    buckets: Sequence[float] = DEFAULT_BUCKETS,
    registry: Optional[Registry] = None,
) -> Histogram:
    return Histogram(name, help_text, labelnames, buckets, registry or _default_registry)
