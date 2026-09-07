# Phase 24 — Observability

Production observability for the hyperlocal platform: **structured logs**,
**metrics**, **alerts** and **health checks** — with a hard guarantee that
secrets (passwords, OTPs, tokens, payment data, private keys, unnecessary
personal data) never reach a log sink.

The stack is **entirely standard-library based** for the metrics engine (no
`prometheus-client` dependency), so it runs identically on the Python 3.14
runtime, in CI, and inside the Docker image.

---

## 1. What is tracked

| Signal | Metrics |
| --- | --- |
| API errors / request latency | `hl_http_requests_total`, `hl_http_errors_total`, `hl_http_5xx_total`, `hl_http_request_duration_seconds` (histogram), `hl_rate_limit_rejections_total` |
| Database errors | `hl_db_errors_total{kind}` + `hl_db_available` |
| Redis errors | `hl_redis_errors_total{op}` + `hl_redis_available` |
| S3 failures | `hl_storage_failures_total{op,provider}`, `hl_storage_operations_total`, `hl_storage_available` |
| Authentication failures | `hl_auth_attempts_total{channel}`, `hl_auth_failures_total{channel,reason}` (`otp`, `access_token`, `refresh_token`, `shopkeeper_*`) |
| Background jobs | `hl_background_jobs_total{task,event}`, `hl_background_jobs_active{task}`, `hl_background_job_duration_seconds{task,event}`, `hl_background_queue_length{queue}` |
| Deployment status | `hl_deployment_info{commit,build_id,version,environment}`, `hl_deployment_timestamp_seconds`, `hl_deployments_total{environment,result}` |
| Resource usage | `hl_process_rss_bytes`, `hl_process_virtual_memory_bytes`, `hl_process_cpu_seconds_total`, `hl_process_threads`, `hl_process_open_fds`, `hl_process_start_time_seconds`, `hl_system_load_{1,5,15}` |
| Application health | `hl_health_component{component}`, `hl_health_checks_total{result}` |
| Alerts | `hl_alerts_fired_total{rule,severity}`, `hl_alert_active{rule}` |

All endpoints/error paths are also **logged as structured JSON access logs**
with request id, correlation id, method, path (cardinality-bounded), status,
duration, client IP and scrubbed query parameters.

### Label cardinality is bounded

Request paths are normalised before use as metric/log labels
(`/api/v1/shops/42` → `/api/v1/shops/{id}`) and task labels are truncated,
so series count stays bounded under arbitrary input.

---

## 2. Structured logs + redaction

### JSON log lines

Every log line (through `app/core/logging.py` `JsonFormatter`) carries:

```json
{
  "timestamp": "...", "level": "INFO", "logger": "app.main",
  "message": "...",
  "service": "hyperlocal-customer-api",
  "environment": "production", "version": "1.0.0", "hostname": "...",
  "request_id": "...", "correlation_id": "..."
}
```

Static labels (`LOG_EXTRA_FIELDS=node=api-1,shard=0`) are merged into every
line so multi-container deployments are filterable by node.

### Redaction (never log secrets)

`app/core/observability/redact.py` implements the only pipeline for
outgoing log messages and structured `extra` payloads:

* inline `password=` / `api_key=` / `client_secret=` / `otp:` assignments
* JWT / bearer / opaque tokens (`eyJ...` patterns)
* private key blocks (`-----BEGIN ... PRIVATE KEY-----`)
* payment card numbers
* key-aware dict redaction — any dict key that looks like `otp`, `token`,
  `authorization`, `password`, `api_key`, `client_secret`, `card_number`,
  `cvv`, `upi`, … gets its value fully replaced with `[REDACTED]`
  (including numeric/object values).

Callers are encouraged to never *place* secrets in logs in the first place;
the formatter redacts as a defence-in-depth last line.

### Request logging

`app/core/observability/access_log.py` emits one JSON line per request via
`AccessLogMiddleware` (`event: "http_request"`). Query strings are scrubbed
through the same redaction rules (OTP/token query params become
`[REDACTED]`).
---

## 3. Metrics

### Storage engine

`app/core/observability/registry.py` implements `Counter`, `Gauge`,
`Histogram` and `Registry` from scratch — thread-safe, Prometheus text
format 0.0.4. `app/core/observability/metrics.py` defines the platform
metric set and helpers (`record_http_request`, `record_db_error`,
`record_auth_result`, …).

### Scrape endpoint — `GET /metrics`

* Outside the `/api/v1` prefix (infra probes don't need auth).
* Returns `text/plain; version=0.0.4`.
* When `METRICS_TOKEN` is set, requires `Authorization: Bearer <token>`;
  leave empty when the endpoint is only reachable from the VPC / an
  internal load balancer.
* Resource gauges are refreshed on every scrape (cheap, cached).

### Admin overview

* `GET /admin/observability/overview` — JSON snapshot of every set scalar
  metric + firing alerts + history (admin `analytics:read`).
* `GET /admin/observability/alerts` — firing alerts + bounded history.

---

## 4. Alerts

`app/core/observability/alerting.py` is a self-contained threshold engine:

* rules evaluate a predicate (e.g. HTTP error rate > 10%, auth-failure
  burst >= 20, storage/db/redis error bursts, component down gauges)
* **delta math** — counters are baselined at first evaluation; the 60 s
  sweep compares *since-last* deltas, so boot noise and long uptime can't
  false-positive
* firing/resolved lifecycle with ring-buffer history (500 entries)
* notifiers: structured `LogNotifier` (always) + optional
  `WebhookNotifier` (`ALERT_WEBHOOK_URL`, posts to Alertmanager/Slack…)

Rules run from beat task `app.core.tasks.evaluate_alert_rules` (every 60
seconds) via the `observe.evaluate-alerts` schedule entry.

### Shipped rules

| rule | condition | severity |
| --- | --- | --- |
| `database_unreachable` | DB probe failed | critical |
| `redis_unreachable` | Redis probe failed | critical |
| `storage_unavailable` | object storage probe failed | warning |
| `storage_failure_burst` | >= 10 storage failures / window | warning |
| `auth_failure_burst` | >= 20 auth failures / window | critical |
| `http_error_rate_high` | error rate > 10% (>= 50 reqs) | warning |
| `http_latency_high` | avg latency > 2s | warning |
| `background_job_failures` | any task failed / window | warning |
| `redis_error_burst` | >= 20 redis errors / window | warning |
| `db_error_burst` | >= 20 db errors / window | warning |

---

## 5. Health checks

* `GET /health` — liveness; returns `{"status": "healthy", …,
  "deployment": {...}}`.
* `GET /ready` — readiness; probes **database, redis, postgis, storage
  and the background-job queue**, returns `200` when all pass and `503`
  otherwise (orchestrators/LB steer traffic away). The Docker HEALTHCHECK
  already uses `/ready`.

Every probe updates `hl_health_component{component}` + `hl_db_available` /
`hl_redis_available` / `hl_storage_available` so the scraped metrics
reflect the last observed component state.

---

## 6. Background job observability

Celery signals (`app/core/observability/celery_signals.py`, installed from
`app/core/celery_app.py`) push every task lifecycle into metrics:

- `task_received` → counter
- `task_prerun` → active gauge +1, counter `started`
- `task_success` / `task_failure` → gauge -1, counter, latency histogram
- `task_retry` → counter

Beat also runs `app.core.tasks.sample_resource_usage` (every 30 s) so
resource time-series exist even without scraper traffic.

---

## 7. Configuration (new env vars)

| Variable | Default | Purpose |
| --- | --- | --- |
| `LOG_SERVICE_NAME` | `hyperlocal-customer-api` | `service` label on every log line |
| `LOG_EXTRA_FIELDS` | `""` | static comma-separated `k=v` labels per node |
| `METRICS_TOKEN` | *(empty)* | bearer token for `GET /metrics` |
| `ALERT_WEBHOOK_URL` | *(empty)* | POST firing/resolved alert events |

Added to `backend/.env.example` / `backend/.env.production.example`.

---

## 8. Never logged

| data | handling |
| --- | --- |
| passwords / passphrases | redacted in messages and dict payloads |
| OTP / verification codes | redacted; responses carry only generic errors |
| JWT / refresh / bearer tokens | redacted; token *values* never logged |
| payment secrets / card numbers | redacted |
| private keys | redacted |
| personal data | not logged unless operationally necessary; query params scrubbed |

The OTP send endpoints log **no OTP digits**; the mock dev path prints the
dev OTP to the console only while `OTP_DEV_MODE` is enabled.

---

## 9. Verification

```bash
python -m pytest tests/test_observability_phase24.py -v     # 36 tests
curl -s localhost:8000/metrics                                # Prometheus text
curl -s localhost:8000/health                                 # liveness + deployment
curl -s localhost:8000/ready                                  # readiness (200/503)
curl -s -H "Authorization: Bearer <METRICS_TOKEN>" localhost:8000/metrics
```