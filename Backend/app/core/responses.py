from typing import Any, Optional
from fastapi.responses import JSONResponse


def success_response(data: Any = None, message: str = "Success", status_code: int = 200) -> JSONResponse:
    """Return a consistent success response body."""
    return JSONResponse(
        status_code=status_code,
        content={
            "success": True,
            "message": message,
            "data": data,
        },
    )


def error_response(
    message: str,
    error_code: str = "ERROR",
    status_code: int = 400,
    data: Optional[Any] = None,
) -> JSONResponse:
    """Return a consistent error response body."""
    return JSONResponse(
        status_code=status_code,
        content={
            "success": False,
            "message": message,
            "error_code": error_code,
            "data": data,
        },
    )