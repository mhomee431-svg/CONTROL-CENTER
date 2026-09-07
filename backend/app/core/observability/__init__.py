"""Phase 24 — Observability subsystem.

A self-contained production observability stack built on the standard
library only (no new third-party dependencies, so it runs identically on
the Python 3.14 runtime and inside the Docker image):

    * metrics      — Prometheus text-format counters / gauges / histograms
                     exposed at ``GET /metrics`` (scrapeable by Prometheus,
                     CloudWatch agent, or any text collector)
    * structured logs — JSON request/log lines enriched with service,
                     environment, version, request/correlation id, and a
                     hard redaction guarantee for secrets (passwords, OTPs,
                     tokens, payment data, private keys)
    * alerts       — threshold-based rule engine with firing/resolved
                     lifecycle, ring-buffer history and pluggable notifiers
                     (log, webhook, email)
    * health       — rich ``/health`` + ``/ready`` probes that also drive
                     the component-availability gauges
    * background jobs — Celery signal hooks that record task success /
                     failure / retry / latency and active-task gauges
    * resource usage  — process/OS resource sampling (memory, CPU, threads,
                     open fds, load) for capacity planning alarms
    * deployment   — build/deploy metadata (commit, build id, started-at)
                     exposed as ``hl_deployment_info``.

Everything that must never appear in a log line (passwords, OTPs, JWT /
bearer tokens, payment secrets, private keys, unnecessary personal data) is
scrubbed by :mod:`app.core.observability.redact` before it reaches a sink.

Sub-modules are imported lazily (import ``app.core.observability.metrics``
directly) so that importing this package alone has no side effects.
"""

__all__ = []