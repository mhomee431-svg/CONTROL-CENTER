"""Global error handling middleware and exception handlers.

Provides consistent error responses for all API endpoints.
"""
import logging
import traceback
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sqlalchemy.exc import IntegrityError, OperationalError

from app.core.exceptions import (
    AppError,
    ForbiddenError,
    NotFoundError,
    UnauthorizedError,
    ValidationError,
)

logger = logging.getLogger("app.core.error_handlers")


def setup_exception_handlers(app: FastAPI) -> None:
    """Register all exception handlers with the FastAPI app."""
    
    @app.exception_handler(AppError)
    async def app_error_handler(request: Request, exc: AppError) -> JSONResponse:
        """Handle custom application errors."""
        return JSONResponse(
            status_code=exc.status_code,
            content={
                "success": False,
                "message": exc.message,
                "error_code": exc.error_code,
                "details": exc.data,
            },
        )
    
    @app.exception_handler(UnauthorizedError)
    async def unauthorized_error_handler(request: Request, exc: UnauthorizedError) -> JSONResponse:
        """Handle authentication errors."""
        return JSONResponse(
            status_code=401,
            content={
                "success": False,
                "message": exc.message,
                "error_code": exc.error_code or "UNAUTHORIZED",
            },
        )
    
    @app.exception_handler(ForbiddenError)
    async def forbidden_error_handler(request: Request, exc: ForbiddenError) -> JSONResponse:
        """Handle authorization errors."""
        return JSONResponse(
            status_code=403,
            content={
                "success": False,
                "message": exc.message,
                "error_code": exc.error_code or "FORBIDDEN",
            },
        )
    
    @app.exception_handler(NotFoundError)
    async def not_found_error_handler(request: Request, exc: NotFoundError) -> JSONResponse:
        """Handle not found errors."""
        return JSONResponse(
            status_code=404,
            content={
                "success": False,
                "message": exc.message,
                "error_code": exc.error_code or "NOT_FOUND",
            },
        )
    
    @app.exception_handler(ValidationError)
    async def validation_error_handler(request: Request, exc: ValidationError) -> JSONResponse:
        """Handle validation errors."""
        return JSONResponse(
            status_code=422,
            content={
                "success": False,
                "message": exc.message,
                "error_code": exc.error_code or "VALIDATION_ERROR",
            },
        )
    
    @app.exception_handler(RequestValidationError)
    async def request_validation_error_handler(
        request: Request, exc: RequestValidationError
    ) -> JSONResponse:
        """Handle FastAPI request validation errors."""
        errors = []
        for error in exc.errors():
            errors.append({
                "field": ".".join(str(loc) for loc in error["loc"]),
                "message": error["msg"],
                "type": error["type"],
            })
        
        return JSONResponse(
            status_code=422,
            content={
                "success": False,
                "message": "Validation error",
                "error_code": "VALIDATION_ERROR",
                "details": {"errors": errors},
            },
        )
    
    @app.exception_handler(IntegrityError)
    async def integrity_error_handler(request: Request, exc: IntegrityError) -> JSONResponse:
        """Handle database integrity errors."""
        logger.error("Database integrity error: %s", exc)
        return JSONResponse(
            status_code=409,
            content={
                "success": False,
                "message": "Data conflict - record already exists or violates constraints",
                "error_code": "INTEGRITY_ERROR",
            },
        )
    
    @app.exception_handler(OperationalError)
    async def operational_error_handler(request: Request, exc: OperationalError) -> JSONResponse:
        """Handle database operational errors."""
        logger.error("Database operational error: %s", exc)
        return JSONResponse(
            status_code=503,
            content={
                "success": False,
                "message": "Service temporarily unavailable",
                "error_code": "DATABASE_ERROR",
            },
        )
    
    @app.exception_handler(Exception)
    async def generic_error_handler(request: Request, exc: Exception) -> JSONResponse:
        """Handle all unhandled exceptions."""
        logger.exception("Unhandled exception: %s", exc)
        return JSONResponse(
            status_code=500,
            content={
                "success": False,
                "message": "Internal server error" if True else str(exc),
                "error_code": "INTERNAL_ERROR",
            },
        )
