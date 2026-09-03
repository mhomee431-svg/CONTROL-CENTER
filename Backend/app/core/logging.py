"""Structured logging setup with request/correlation ID context enrichment.

Phase 24 (observability) additions:

* **Redaction** — every message and every ``extra`` field is passed through
  :func:`app.core.observability.redact.redact_message` before serialization
  so passwords / OTPs / tokens / payment data can never reach a sink, even
  if a caller accidentally places them in a log call.
* **Service labels** — ``service``, ``environment``, ``version`` and any
  ``LOG_EXTRA_FIELDS`` (``node=api-1,shard=0``) are attached to every JSON
  line so log-shippers can filter/route reliably.
* **Structured extra data** — callers may pass ``extra={"data": {...}}``; the
  dict is merged into the output JSON (redacted) instead of being dropped.
"""

import contextvars
import json
import logging
import socket
import sys
from datetime import datetime, timezone
from logging.handlers import RotatingFileHandler
from pathlib import Path

from app.core.config import settings
from app.core.observability.redact import is_secret_key, redact_message

# Context variables for request/correlation IDs (set by middleware)
request_id_var: contextvars.ContextVar = contextvars.ContextVar("request_id", default="-")
correlation_id_var: contextvars.ContextVar = contextvars.ContextVar(
    "correlation_id", default="-"
)

#: Hostname of this process (used as a fixed production label).
_HOSTNAME = socket.gethostname()


def _parse_extra_fields(raw: str) -> dict:
    """Parse ``LOG_EXTRA_FIELDS`` like ``node=api-1,shard=0`` into a dict."""
    out: dict = {}
    for part in (raw or "").split(","):
        part = part.strip()
        if not part or "=" not in part:
            continue
        key, _, value = part.partition("=")
        out[key.strip()] = value.strip()
    return out


class JsonFormatter(logging.Formatter):
    """JSON formatter that includes context, service labels, and redaction."""

    def __init__(self) -> None:
        super().__init__()
        self.service = settings.LOG_SERVICE_NAME
        self.environment = settings.ENVIRONMENT
        self.version = settings.APP_VERSION
        self.static_fields = _parse_extra_fields(settings.LOG_EXTRA_FIELDS)

    @staticmethod
    def _redact_recursive(value):
        """Walk a value and redact every string leaf (lists / dicts included).

        Dict keys are checked against secret hints first so ``{"otp": "482913"}``
        redacts even though the bare value ``"482913"`` has no inline key.
        """
        if isinstance(value, dict):
            out: dict = {}
            for key, val in value.items():
                if is_secret_key(key):
                    out[key] = "[REDACTED]"
                else:
                    out[key] = JsonFormatter._redact_recursive(val)
            return out
        if isinstance(value, (list, tuple)):
            return [JsonFormatter._redact_recursive(item) for item in value]
        if isinstance(value, str):
            return redact_message(value)
        return value

    def format(self, record: logging.LogRecord) -> str:
        data = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": redact_message(record.getMessage()),
            "service": self.service,
            "environment": self.environment,
            "version": self.version,
            "hostname": _HOSTNAME,
        }
        # Apply static LOG_EXTRA_FIELDS (node=..., shard=...).
        for key, value in self.static_fields.items():
            data[key] = value
        # Attach context fields when present.
        if hasattr(record, "request_id"):
            data["request_id"] = record.request_id
        if hasattr(record, "correlation_id"):
            data["correlation_id"] = record.correlation_id
        if hasattr(record, "user_id"):
            data["user_id"] = record.user_id
        if getattr(record, "path", None):
            data["path"] = record.path
        if record.exc_info:
            data["exc_info"] = self.formatException(record.exc_info)
        # Merge structured ``extra={"data": {...}}`` payloads (redacted).
        extra_data = getattr(record, "data", None)
        if isinstance(extra_data, dict):
            for key, value in extra_data.items():
                if is_secret_key(key):
                    data[key] = "[REDACTED]"
                else:
                    data[key] = self._redact_recursive(value)
        return json.dumps(data, default=str)


class ContextFilter(logging.Filter):
    """Attach request/correlation IDs from contextvars to log records."""

    def filter(self, record: logging.LogRecord) -> bool:
        record.request_id = request_id_var.get()
        record.correlation_id = correlation_id_var.get()
        return True


def setup_logging() -> None:
    """Configure the root logger with console + optional file handlers."""
    root = logging.getLogger()
    root.setLevel(getattr(logging, settings.LOG_LEVEL.upper(), logging.INFO))

    # Avoid duplicate handlers on reload
    for handler in list(root.handlers):
        root.removeHandler(handler)

    if settings.LOG_FORMAT == "json":
        formatter: logging.Formatter = JsonFormatter()
    else:
        formatter = logging.Formatter(
            "%(asctime)s - %(name)s - %(levelname)s - "
            "[request_id=%(request_id)s correlation_id=%(correlation_id)s] - %(message)s"
        )

    ctx_filter = ContextFilter()

    console = logging.StreamHandler(sys.stdout)
    console.setFormatter(formatter)
    console.addFilter(ctx_filter)
    root.addHandler(console)

    if settings.LOG_FILE_ENABLED:
        base_path = Path(settings.LOG_FILE_PATH)
        base_path.parent.mkdir(parents=True, exist_ok=True)
        fh = RotatingFileHandler(
            str(base_path),
            maxBytes=settings.LOG_MAX_BYTES,
            backupCount=settings.LOG_BACKUP_COUNT,
            encoding="utf-8",
        )
        fh.setFormatter(formatter)
        fh.addFilter(ctx_filter)
        root.addHandler(fh)

    # Suppress verbose library logs
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)
    logging.getLogger("uvicorn.error").setLevel(logging.INFO)
    logging.getLogger("sqlalchemy.engine").setLevel(logging.WARNING)
    logging.getLogger("celery").setLevel(logging.WARNING)
    logging.getLogger("alembic").setLevel(logging.INFO)


def get_logger(name: str) -> logging.Logger:
    return logging.getLogger(name)


def set_context(request_id: str, correlation_id: str) -> None:
    """Set the current contextvars for logging enrichment."""
    request_id_var.set(request_id)
    correlation_id_var.set(correlation_id)