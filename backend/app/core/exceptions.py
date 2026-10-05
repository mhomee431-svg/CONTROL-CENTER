"""Global exception handlers with structured logging and request context."""

from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sqlalchemy.exc import IntegrityError, SQLAlchemyError

from app.core.logging import get_logger
from app.core.observability.metrics import record_db_error

logger = get_logger("app.exceptions")


class AppError(Exception):
    """Base application error with HTTP status + error code."""

    def __init__(
        self,
        message: str,
        error_code: str = "APP_ERROR",
        status_code: int = 400,
        data: dict[str, Any] | None = None,
    ):
        self.message = message
        self.error_code = error_code
        self.status_code = status_code
        self.data = data
        super().__init__(message)


class NotFoundError(AppError):
    def __init__(self, message: str = "Resource not found"):
        super().__init__(message, "NOT_FOUND", 404)


class UnauthorizedError(AppError):
    def __init__(
        self,
        message: str = "Unauthorized",
        code: str = "UNAUTHORIZED",
        data: dict[str, Any] | None = None,
    ):
        # `code` is overridable so a caller that knows WHY the request was
        # rejected can say so â€” e.g. Firebase's "token-expired" vs
        # "user-not-found". Both stay 401; only the machine-readable reason
        # differs, which is what a client needs to decide between "sign in
        # again" and "this account no longer exists".
        super().__init__(message, code, 401, data)


class ForbiddenError(AppError):
    def __init__(
        self,
        message: str = "Forbidden",
        code: str = "FORBIDDEN",
        data: dict[str, Any] | None = None,
    ):
        # `code` optional so a caller can name the specific reason without
        # changing the status. See UnauthorizedError for why the distinction
        # matters.
        super().__init__(message, code, 403, data)


class ValidationError(AppError):
    def __init__(self, message: str = "Validation error", data: dict[str, Any] | None = None):
        super().__init__(message, "VALIDATION_ERROR", 422, data)


class ConflictError(AppError):
    def __init__(self, message: str = "Conflict"):
        super().__init__(message, "CONFLICT", 409)


class RateLimitError(AppError):
    def __init__(self, message: str = "Rate limit exceeded"):
        super().__init__(message, "RATE_LIMIT_EXCEEDED", 429)


class ServiceUnavailableError(AppError):
    def __init__(self, message: str = "Service temporarily unavailable"):
        super().__init__(message, "SERVICE_UNAVAILABLE", 503)


def _request_context(request: Request) -> dict[str, Any]:
    """Extract request metadata for logging."""
    return {
        "path": request.url.path,
        "method": request.method,
        "request_id": getattr(request.state, "request_id", "-"),
        "correlation_id": getattr(request.state, "correlation_id", "-"),
    }


def setup_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(AppError)
    async def app_error_handler(request: Request, exc: AppError):
        ctx = _request_context(request)
        logger.warning(
            "AppError: %s (%s) path=%s method=%s request_id=%s",
            exc.message,
            exc.error_code,
            ctx["path"],
            ctx["method"],
            ctx["request_id"],
        )
        body = {
            "success": False,
            "message": exc.message,
            "error_code": exc.error_code,
        }
        if exc.data is not None:
            body["data"] = exc.data
        return JSONResponse(status_code=exc.status_code, content=body)

    @app.exception_handler(RequestValidationError)
    async def validation_error_handler(request: Request, exc: RequestValidationError):
        ctx = _request_context(request)
        
        # Format errors for client
        formatted_errors = []
        for error in exc.errors():
            formatted_errors.append({
                "field": ".".join(str(loc) for loc in error["loc"]),
                "message": error["msg"],
                "type": error["type"],
            })
        
        logger.warning(
            "ValidationError path=%s method=%s request_id=%s errors=%s",
            ctx["path"],
            ctx["method"],
            ctx["request_id"],
            exc.errors(),
        )
        return JSONResponse(
            status_code=422,
            content={
                "success": False,
                "message": "Validation error",
                "error_code": "VALIDATION_ERROR",
                "data": {"errors": formatted_errors},
            },
        )

    @app.exception_handler(IntegrityError)
    async def integrity_error_handler(request: Request, exc: IntegrityError):
        ctx = _request_context(request)
        record_db_error("integrity")
        logger.error(
            "IntegrityError path=%s request_id=%s error=%s",
            ctx["path"],
            ctx["request_id"],
            exc,
        )
        return JSONResponse(
            status_code=409,
            content={
                "success": False,
                "message": "Data integrity violation",
                "error_code": "INTEGRITY_ERROR",
            },
        )

    @app.exception_handler(SQLAlchemyError)
    async def db_error_handler(request: Request, exc: SQLAlchemyError):
        ctx = _request_context(request)
        record_db_error("statement")
        logger.error(
            "SQLAlchemyError path=%s request_id=%s error=%s",
            ctx["path"],
            ctx["request_id"],
            exc,
        )
        return JSONResponse(
            status_code=500,
            content={
                "success": False,
                "message": "Database error occurred",
                "error_code": "DATABASE_ERROR",
            },
        )

    @app.exception_handler(Exception)
    async def unhandled_error_handler(request: Request, exc: Exception):
        ctx = _request_context(request)
        logger.exception(
            "Unhandled error path=%s method=%s request_id=%s error=%s",
            ctx["path"],
            ctx["method"],
            ctx["request_id"],
            exc,
        )
        return JSONResponse(
            status_code=500,
            content={
                "success": False,
                "message": "Internal server error",
                "error_code": "INTERNAL_ERROR",
            },
        )