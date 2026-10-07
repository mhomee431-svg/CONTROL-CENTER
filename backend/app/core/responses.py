"""Standard response envelope.

The frontend's apiClient unwraps `data.data` and reads `data.message` /
`data.error_code` on failure, so every route returns this shape rather than a
bare object. One envelope means the client has one parsing path.
"""

from typing import Any, Generic, Optional, TypeVar

from pydantic import BaseModel

T = TypeVar("T")


class ApiResponse(BaseModel, Generic[T]):
    success: bool = True
    message: str = "OK"
    data: Optional[T] = None
    error_code: Optional[str] = None


def ok(data: Any = None, message: str = "OK") -> dict[str, Any]:
    return {"success": True, "message": message, "data": data}


def paged(items: list[Any], total: int, **extra: Any) -> dict[str, Any]:
    """List envelope. `items`/`total` is what `fetchList` reads."""
    payload: dict[str, Any] = {"items": items, "total": total}
    payload.update(extra)
    return payload
