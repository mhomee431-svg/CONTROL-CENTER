"""Storage service abstraction — Local Disk, S3, and Cloudinary providers.

The provider is selected via `STORAGE_PROVIDER` config and can be swapped
without changing application code. No provider secrets are hardcoded.

Phase 7 — S3 object storage:
    * signed-upload architecture: Flutter → backend authorization →
      short-lived signed upload policy → S3 (credentials NEVER leave the
      backend; the signed URL embeds only the permission to PUT one object,
      with content-type and size enforced by the policy conditions)
    * filename/key strategy: `{prefix}/{scope}/{YYYY}/{MM}/{uuid8}_{name}.{ext}`
      via :func:`build_object_key` (sanitized, collision-proof, time-partitioned)
    * typed failure handling: provider outages surface as
      :class:`StorageUnavailableError` (HTTP 503) instead of 500s
"""

import io
import re
import uuid
from abc import ABC, abstractmethod
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

from app.core.config import settings
from app.core.exceptions import ServiceUnavailableError
from app.core.logging import get_logger

logger = get_logger("app.storage")


class StorageUnavailableError(ServiceUnavailableError):
    """Object-storage backend unreachable or failing — fail closed as 503."""

    def __init__(self, message: str = "Storage service is temporarily unavailable"):
        super().__init__(message)
        self.error_code = "STORAGE_UNAVAILABLE"


def _storage_exc(exc: Exception, action: str) -> StorageUnavailableError:
    """Wrap an unexpected storage backend failure into a typed 503 error."""
    logger.error("Storage %s failed: %s", action, exc)
    return StorageUnavailableError(f"Storage {action} failed; please retry shortly")


# ── Key strategy ─────────────────────────────────────────────────────────────

_KEY_UNSAFE = re.compile(r"[^A-Za-z0-9._-]")
_KEY_MAX_BASENAME = 64


def build_object_key(folder: str, filename: str) -> str:
    """Build a safe, unique, time-partitioned object key.

    ``{folder}/{YYYY}/{MM}/{uuid8}_{sanitized-basename}``

    * folder: category prefix (e.g. ``products/12``) — trusted, server-minted
    * basename: untrusted filename → sanitized, stripped of any path parts,
      control chars removed, capped at 64 chars
    * uuid8: guarantees uniqueness (no overwrite of another user's object)
    """
    from app.core.upload_security import sanitize_filename

    safe = _KEY_UNSAFE.sub("_", sanitize_filename(filename, fallback="file"))
    # Keep the extension readable but tame the stem.
    stem = Path(safe).stem[:_KEY_MAX_BASENAME] or "file"
    suffix = Path(safe).suffix.lower()[:16]
    now = datetime.now(timezone.utc)
    return (
        f"{folder.rstrip('/')}/{now:%Y}/{now:%m}/"
        f"{uuid.uuid4().hex[:8]}_{stem}{suffix}"
    )


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

    # ── Phase 7 — signed upload / object inspection ──────────────────────────

    async def create_signed_upload(
        self,
        key: str,
        content_type: str,
        max_bytes: int,
        expires_in: Optional[int] = None,
    ) -> dict:
        """Return a short-lived signed upload grant for ONE object key.

        Returns ``{"mode": "post", "url", "fields"}`` (browser/mobile POSTs
        the multipart form to S3) or ``{"mode": "direct"}`` when the provider
        requires the backend to stream the bytes (local development).
        The grant embeds content-type and ``content-length-range`` conditions
        so S3 itself rejects wrong-type or oversized payloads.
        """
        raise NotImplementedError

    async def get_object_head(self, key: str) -> Optional[dict]:
        """Return ``{"size", "content_type"}`` for the object, or None if absent.

        Raises :class:`StorageUnavailableError` on backend failure.
        """
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

    def presign_get_sync(self, key: str) -> str:
        """Sync URL resolution for serializers (local: static path)."""
        return f"/static/uploads/{key}"

    async def create_signed_upload(
        self,
        key: str,
        content_type: str,
        max_bytes: int,
        expires_in: Optional[int] = None,
    ) -> dict:
        # Local disk has no signing concept: the backend streams the bytes
        # itself via POST /media/direct-upload (full validation in-process).
        return {"mode": "direct", "key": key, "max_bytes": max_bytes}

    async def get_object_head(self, key: str) -> Optional[dict]:
        try:
            path = self.upload_dir / key
            if not path.is_file():
                return None
            return {
                "size": path.stat().st_size,
                # Files were stored with the declared content type at upload.
                "content_type": _LOCAL_CONTENT_TYPES.get(path.suffix.lower()),
            }
        except OSError as exc:  # pragma: no cover - disk failure
            raise _storage_exc(exc, "head") from exc


# Best-effort content-type recall for local dev files (stored flat on disk).
_LOCAL_CONTENT_TYPES = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".webp": "image/webp",
    ".pdf": "application/pdf",
}


class S3StorageProvider(BaseStorageProvider):
    """Store files on AWS S3 (or S3-compatible: MinIO, Wasabi, etc.)."""

    def __init__(self):
        import boto3

        self.bucket = settings.S3_BUCKET_NAME
        if not self.bucket:
            raise ValueError("S3_BUCKET_NAME is required when STORAGE_PROVIDER=s3")

        kwargs = {"region_name": settings.S3_REGION}
        # Static keys are OPTIONAL. When absent, boto3 uses the instance/ECS
        # IAM role (default credential chain) — the recommended production path.
        if settings.S3_ACCESS_KEY_ID:
            kwargs["aws_access_key_id"] = settings.S3_ACCESS_KEY_ID
        if settings.S3_SECRET_ACCESS_KEY:
            kwargs["aws_secret_access_key"] = settings.S3_SECRET_ACCESS_KEY
        if settings.S3_ENDPOINT_URL:
            kwargs["endpoint_url"] = settings.S3_ENDPOINT_URL

        self.client = boto3.client("s3", **kwargs)
        self.acl = settings.S3_ACL.lower()

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

        extra = {"ContentType": content_type}
        # Apply ACL only when supported; private buckets simply omit it.
        if self.acl != "private":
            extra["ACL"] = self.acl

        try:
            self.client.upload_fileobj(
                io.BytesIO(file_bytes),
                self.bucket,
                key,
                ExtraArgs=extra,
            )
        except Exception as exc:  # noqa: BLE001
            raise _storage_exc(exc, "upload") from exc
        return f"s3://{self.bucket}/{key}"

    async def create_signed_upload(
        self,
        key: str,
        content_type: str,
        max_bytes: int,
        expires_in: Optional[int] = None,
    ) -> dict:
        """Presigned POST policy for exactly one object key.

        Conditions enforce, AT S3 (before the object can ever exist):
          * content-type must equal the backend-validated type
          * body length is between 1 byte and the category cap
          * key is fixed (client cannot choose another path)
        """
        from app.core.config import settings as _settings

        ttl = int(expires_in or _settings.S3_UPLOAD_URL_EXPIRES_SECONDS)
        conditions = [
            {"bucket": self.bucket},
            ["content-length-range", 1, max_bytes],
            {"key": key},
            {"Content-Type": content_type},
        ]
        try:
            post = self.client.generate_presigned_post(
                Bucket=self.bucket,
                Key=key,
                Conditions=conditions,
                ExpiresIn=ttl,
            )
        except Exception as exc:  # noqa: BLE001
            raise _storage_exc(exc, "signed-upload") from exc
        return {
            "mode": "post",
            "url": post["url"],
            "fields": post["fields"],
            "key": key,
            "expires_in": ttl,
            "content_type": content_type,
            "max_bytes": max_bytes,
        }

    async def get_object_head(self, key: str) -> Optional[dict]:
        import botocore.exceptions as bexc

        try:
            head = self.client.head_object(Bucket=self.bucket, Key=key)
        except bexc.ClientError as exc:
            code = getattr(exc, "response", {}).get("Error", {}).get("Code", "")
            status = getattr(exc, "response", {}).get("ResponseMetadata", {}).get("HTTPStatusCode")
            if code in ("404", "NoSuchKey", "NotFound") or status == 404:
                return None
            raise _storage_exc(exc, "head") from exc
        except Exception as exc:  # noqa: BLE001 — network/endpoint failures
            raise _storage_exc(exc, "head") from exc
        return {
            "size": int(head.get("ContentLength", 0)),
            "content_type": head.get("ContentType"),
        }

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
        # For private buckets return a short-lived presigned URL so we NEVER
        # expose S3 credentials and never require public-read objects.
        if self.acl == "private":
            try:
                return self.client.generate_presigned_url(
                    "get_object",
                    Params={"Bucket": self.bucket, "Key": key},
                    ExpiresIn=settings.S3_DOWNLOAD_URL_EXPIRES_SECONDS,
                )
            except Exception as exc:  # noqa: BLE001
                raise _storage_exc(exc, "presign") from exc
        if settings.S3_ENDPOINT_URL:
            return f"{settings.S3_ENDPOINT_URL}/{self.bucket}/{key}"
        return f"https://{self.bucket}.s3.{settings.S3_REGION}.amazonaws.com/{key}"

    def presign_get_sync(self, key: str) -> str:
        """Sync presigned GET for serializers (boto3 call is sync anyway).

        Same guarantees as :meth:`get_file_url`: short-lived URL, no
        credentials exposed, private objects never need public ACLs.
        """
        key = key.replace(f"s3://{self.bucket}/", "")
        if self.acl != "private":
            if settings.S3_ENDPOINT_URL:
                return f"{settings.S3_ENDPOINT_URL}/{self.bucket}/{key}"
            return f"https://{self.bucket}.s3.{settings.S3_REGION}.amazonaws.com/{key}"
        return self.client.generate_presigned_url(
            "get_object",
            Params={"Bucket": self.bucket, "Key": key},
            ExpiresIn=settings.S3_DOWNLOAD_URL_EXPIRES_SECONDS,
        )


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