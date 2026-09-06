"""Standardized API response utilities.

Provides consistent response formatting across all endpoints.
"""
from typing import Any, Optional

from fastapi import Request
from fastapi.responses import JSONResponse


def success_response(
    data: Any = None,
    message: str = "Success",
    status_code: int = 200,
    meta: Optional[dict] = None,
) -> JSONResponse:
    """Build a standardized success response.
    
    Format:
    {
        "success": true,
        "message": "Success",
        "data": {...},
        "meta": {...}  // optional pagination, etc.
    }
    """
    response = {
        "success": True,
        "message": message,
        "data": data,
    }
    
    if meta is not None:
        response["meta"] = meta
    
    return JSONResponse(content=response, status_code=status_code)


def error_response(
    message: str = "An error occurred",
    error_code: str = "ERROR",
    status_code: int = 400,
    details: Any = None,
) -> JSONResponse:
    """Build a standardized error response.
    
    Format:
    {
        "success": false,
        "message": "Error description",
        "error_code": "ERROR_CODE",
        "details": {...}  // optional additional info
    }
    """
    response = {
        "success": False,
        "message": message,
        "error_code": error_code,
    }
    
    if details is not None:
        response["details"] = details
    
    return JSONResponse(content=response, status_code=status_code)


def paginated_response(
    items: list,
    total: int,
    page: int,
    limit: int,
    message: str = "Success",
) -> JSONResponse:
    """Build a standardized paginated response.
    
    Format:
    {
        "success": true,
        "message": "Success",
        "data": {
            "items": [...],
            "pagination": {
                "total": 100,
                "page": 1,
                "limit": 20,
                "pages": 5,
                "has_next": true,
                "has_prev": false
            }
        }
    }
    """
    pages = (total + limit - 1) // limit if limit > 0 else 0
    
    response = {
        "success": True,
        "message": message,
        "data": {
            "items": items,
            "pagination": {
                "total": total,
                "page": page,
                "limit": limit,
                "pages": pages,
                "has_next": page < pages,
                "has_prev": page > 1,
            },
        },
    }
    
    return JSONResponse(content=response, status_code=200)


def created_response(
    data: Any = None,
    message: str = "Created successfully",
) -> JSONResponse:
    """Build a standardized 201 Created response."""
    return success_response(data=data, message=message, status_code=201)


def no_content_response() -> JSONResponse:
    """Build a standardized 204 No Content response."""
    return JSONResponse(content=None, status_code=204)
