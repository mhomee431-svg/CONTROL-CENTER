from typing import Any, Optional

from fastapi.encoders import jsonable_encoder
from fastapi.responses import JSONResponse


def success_response(data: Any = None, message: str = "Success", status_code: int = 200) -> JSONResponse:
    """Return a consistent success response body.

    Payloads are run through ``jsonable_encoder`` so ORM values such as
    ``datetime`` / enums serialize to JSON (Starlette's plain ``JSONResponse``
    would otherwise raise ``TypeError`` on a ``datetime`` — a production bug
    that broke every search/shop-detail response with a non-null
    ``last_inventory_update``).
    """
    return JSONResponse(
        status_code=status_code,
        content=jsonable_encoder(
            {
                "success": True,
                "message": message,
                "data": data,
            }
        ),
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
        content=jsonable_encoder(
            {
                "success": False,
                "message": message,
                "error_code": error_code,
                "data": data,
            }
        ),
    )