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