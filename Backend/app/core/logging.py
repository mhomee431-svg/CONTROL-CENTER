"""Structured logging setup with request/correlation ID context enrichment."""

import contextvars
import json
import logging
import sys
from datetime import datetime, timezone
from logging.handlers import RotatingFileHandler
from pathlib import Path

from app.core.config import settings

# Context variables for request/correlation IDs (set by middleware)
request_id_var: contextvars.ContextVar = contextvars.ContextVar("request_id", default="-")
correlation_id_var: contextvars.ContextVar = contextvars.ContextVar(
    "correlation_id", default="-"
)


class JsonFormatter(logging.Formatter):
    """JSON formatter that includes request/correlation IDs when present."""

    def format(self, record: logging.LogRecord) -> str:
        data = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
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