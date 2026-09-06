"""Base service layer — common service patterns and dependency injection."""

from typing import Any, Generic, Optional, TypeVar

from app.repositories.base import BaseRepository

RepoType = TypeVar("RepoType", bound=BaseRepository)


class BaseService(Generic[RepoType]):
    """Generic service providing common business operations over a repository."""

    def __init__(self, repository: RepoType):
        self.repository = repository

    async def get(self, id: int):
        return await self.repository.get(id)

    async def get_by(self, **kwargs: Any):
        return await self.repository.get_by(**kwargs)

    async def list(self, *, skip: int = 0, limit: int = 100, **filters: Any):
        return await self.repository.list(skip=skip, limit=limit, **filters)

    async def create(self, **kwargs: Any):
        return await self.repository.create(**kwargs)

    async def update(self, id: int, **kwargs: Any):
        return await self.repository.update(id, **kwargs)

    async def delete(self, id: int) -> bool:
        return await self.repository.delete(id)

    async def count(self, **filters: Any) -> int:
        return await self.repository.count(**filters)

    async def exists(self, **filters: Any) -> bool:
        """Check if a record matching the filters exists."""
        count = await self.repository.count(**filters)
        return count > 0

    async def get_or_404(self, id: int):
        """Get a record or raise NotFoundError."""
        from app.core.exceptions import NotFoundError
        
        obj = await self.repository.get(id)
        if obj is None:
            raise NotFoundError(f"{self.repository.model.__name__} with id {id} not found")
        return obj

    async def get_by_or_404(self, **kwargs: Any):
        """Get a record by filters or raise NotFoundError."""
        from app.core.exceptions import NotFoundError
        
        obj = await self.repository.get_by(**kwargs)
        if obj is None:
            raise NotFoundError(f"{self.repository.model.__name__} not found")
        return obj

    async def paginate(
        self,
        *,
        page: int = 1,
        limit: int = 20,
        **filters: Any,
    ) -> dict:
        """Return paginated results with metadata."""
        skip = (page - 1) * limit
        
        from sqlalchemy import select, func
        from app.database.session import AsyncSessionLocal
        
        # Get items
        items = await self.repository.list(skip=skip, limit=limit, **filters)
        
        # Get total count
        total = await self.repository.count(**filters)
        
        pages = (total + limit - 1) // limit if limit > 0 else 0
        
        return {
            "items": items,
            "pagination": {
                "total": total,
                "page": page,
                "limit": limit,
                "pages": pages,
                "has_next": page < pages,
                "has_prev": page > 1,
            },
        }