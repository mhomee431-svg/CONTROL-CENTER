"""Storage service abstraction — Local Disk, S3, and Cloudinary providers.

The provider is selected via `STORAGE_PROVIDER` config and can be swapped
without changing application code. No provider secrets are hardcoded.
"""

import io
import uuid
from abc import ABC, abstractmethod
from pathlib import Path
from typing import Optional

from app.core.config import settings
from app.core.logging import get_logger

logger = get_logger("app.storage")


class BaseStorageProvider(ABC):
    """Interface all storage providers must implement."""

    @abstractmethod
    async def upload_file(
        self,
        file_bytes: bytes,
        filename: str,
        content_type: str = "application/octet-stream",
        folder: Optional[str] = None,
    ) -> str:
        """Upload file and return accessible URL/path."""
        raise NotImplementedError

    @abstractmethod
    async def delete_file(self, file_identifier: str) -> bool:
        """Delete file from storage."""
        raise NotImplementedError

    @abstractmethod
    async def get_file_url(self, file_identifier: str) -> str:
        """Return a public URL for the given file identifier."""
        raise NotImplementedError


class LocalStorageProvider(BaseStorageProvider):
    """Store files on the local filesystem (development / single-node)."""

    def __init__(self, upload_dir: Optional[str] = None):
        self.upload_dir = Path(upload_dir or settings.STORAGE_LOCAL_PATH)
        self.upload_dir.mkdir(parents=True, exist_ok=True)

    async def upload_file(
        self,
        file_bytes: bytes,
        filename: str,
        content_type: str = "application/octet-stream",
        folder: Optional[str] = None,
    ) -> str:
        safe_name = f"{uuid.uuid4().hex}_{Path(filename).name}"
        target_dir = self.upload_dir / folder if folder else self.upload_dir
        target_dir.mkdir(parents=True, exist_ok=True)
        file_path = target_dir / safe_name
        file_path.write_bytes(file_bytes)
        relative = file_path.relative_to(self.upload_dir)
        return f"/static/uploads/{relative.as_posix()}"

    async def delete_file(self, file_identifier: str) -> bool:
        clean = file_identifier.replace("/static/uploads/", "")
        file_path = self.upload_dir / clean
        if file_path.exists():
            file_path.unlink()
            return True
        return False

    async def get_file_url(self, file_identifier: str) -> str:
        return file_identifier


class S3StorageProvider(BaseStorageProvider):
    """Store files on AWS S3 (or S3-compatible: MinIO, Wasabi, etc.)."""

    def __init__(self):
        import boto3

        self.bucket = settings.S3_BUCKET_NAME
        if not self.bucket:
            raise ValueError("S3_BUCKET_NAME is required when STORAGE_PROVIDER=s3")

        kwargs = {
            "region_name": settings.S3_REGION,
            "aws_access_key_id": settings.S3_ACCESS_KEY_ID,
            "aws_secret_access_key": settings.S3_SECRET_ACCESS_KEY,
        }
        if settings.S3_ENDPOINT_URL:
            kwargs["endpoint_url"] = settings.S3_ENDPOINT_URL

        self.client = boto3.client("s3", **kwargs)

    async def upload_file(
        self,
        file_bytes: bytes,
        filename: str,
        content_type: str = "application/octet-stream",
        folder: Optional[str] = None,
    ) -> str:
        key = f"{uuid.uuid4().hex}_{Path(filename).name}"
        if folder:
            key = f"{folder.rstrip('/')}/{key}"

        self.client.upload_fileobj(
            io.BytesIO(file_bytes),
            self.bucket,
            key,
            ExtraArgs={
                "ContentType": content_type,
                "ACL": settings.S3_ACL,
            },
        )
        return f"s3://{self.bucket}/{key}"

    async def delete_file(self, file_identifier: str) -> bool:
        key = file_identifier.replace(f"s3://{self.bucket}/", "")
        try:
            self.client.delete_object(Bucket=self.bucket, Key=key)
            return True
        except Exception as exc:  # noqa: BLE001
            logger.warning("S3 delete failed: %s", exc)
            return False

    async def get_file_url(self, file_identifier: str) -> str:
        key = file_identifier.replace(f"s3://{self.bucket}/", "")
        if settings.S3_ENDPOINT_URL:
            return f"{settings.S3_ENDPOINT_URL}/{self.bucket}/{key}"
        return f"https://{self.bucket}.s3.{settings.S3_REGION}.amazonaws.com/{key}"


class CloudinaryStorageProvider(BaseStorageProvider):
    """Store files on Cloudinary (free-tier friendly)."""

    def __init__(self):
        import cloudinary
        import cloudinary.uploader

        cloudinary.config(
            cloud_name=settings.CLOUDINARY_CLOUD_NAME,
            api_key=settings.CLOUDINARY_API_KEY,
            api_secret=settings.CLOUDINARY_API_SECRET,
        )
        self.uploader = cloudinary.uploader

    async def upload_file(
        self,
        file_bytes: bytes,
        filename: str,
        content_type: str = "application/octet-stream",
        folder: Optional[str] = None,
    ) -> str:
        result = self.uploader.upload(
            io.BytesIO(file_bytes),
            public_id=f"{settings.CLOUDINARY_FOLDER}/{uuid.uuid4().hex}",
            resource_type="auto",
        )
        return result.get("secure_url", result.get("url", ""))

    async def delete_file(self, file_identifier: str) -> bool:
        try:
            public_id = file_identifier.split("/")[-1].split(".")[0]
            self.uploader.destroy(f"{settings.CLOUDINARY_FOLDER}/{public_id}")
            return True
        except Exception as exc:  # noqa: BLE001
            logger.warning("Cloudinary delete failed: %s", exc)
            return False

    async def get_file_url(self, file_identifier: str) -> str:
        return file_identifier


def get_storage_provider() -> BaseStorageProvider:
    """Factory that returns the configured storage provider."""
    provider = settings.STORAGE_PROVIDER.lower()
    if provider == "s3":
        return S3StorageProvider()
    if provider == "cloudinary":
        return CloudinaryStorageProvider()
    return LocalStorageProvider()


# Module-level singleton (lazy — created on first use)
_storage_provider: Optional[BaseStorageProvider] = None


def get_storage() -> BaseStorageProvider:
    global _storage_provider
    if _storage_provider is None:
        _storage_provider = get_storage_provider()
    return _storage_provider