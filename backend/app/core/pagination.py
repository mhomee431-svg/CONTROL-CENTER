"""Shared list query parameters.

Every list surface in the console speaks the same vocabulary — limit/offset
plus free-text search — so it is parsed in one place rather than repeated per
router.
"""

from fastapi import Query
from pydantic import BaseModel


class Pagination(BaseModel):
    limit: int = 25
    offset: int = 0
    search: str | None = None

    def window(self) -> tuple[int, int]:
        return self.offset, self.offset + self.limit


def pagination(
    limit: int = Query(25, ge=1, le=200),
    offset: int = Query(0, ge=0),
    search: str | None = Query(None),
) -> Pagination:
    return Pagination(limit=limit, offset=offset, search=search)
