"""Phase 7 — Media object-storage service (S3-backed, signed-upload flow).

Architecture (credentials NEVER leave the backend, and never reach Flutter):

    Flutter ──(1) POST /media/upload-url (JWT)──▶ Backend
    Backend ──(2) authorize + validate + mint key
    Backend ──(3) signed upload policy (content-type + size conditions)──▶ client
    Flutter ──(4) multipart POST of the file directly to S3
    Flutter ──(5) POST /media/confirm ──▶ Backend HEADs the object and,
                  on success, returns a short-lived read URL

Guarantees:
    * upload      — signed POST policies bound to exactly one server-minted key
    * validation  — extension/content-type allow-lists per category
    * size caps   — enforced by S3 policy conditions AND re-checked at confirm
    * content-type— enforced by S3 policy AND re-checked at confirm (HEAD)
    * key strategy— {prefix}/{scope}/{YYYY}/{MM}/{uuid8}_{safe-name}.{ext}
    * image rules — jpeg/png/webp only, 5 MB cap; documents: pdf, 15 MB cap
    * deletion    — owner/manager/admin only, scoped to the key's owner
    * URL         — private ACL: short-lived presigned GET after authorization
    * failures    — backend outages surface as typed 503 STORAGE_UNAVAILABLE
    * PostgreSQL  — never stores binary media; only object keys/metadata
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any, Optional

from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.exceptions import ForbiddenError, NotFoundError, ValidationError
from app.core.logging import get_logger
from app.core.storage import (
    BaseStorageProvider,
    StorageUnavailableError,
    build_object_key,
    get_storage,
)
from app.core.upload_security import MEDIA_TYPES, validate_media_upload
from app.models.user import User
from app.services import shopkeeper_service

logger = get_logger("app.services.media")


# ── Category registry ────────────────────────────────────────────────────────


@dataclass(frozen=True)
class MediaCategory:
    """Rules for one class of user-uploaded object."""

    name: str
    prefix: str                    # first path segment of every object key
    scope: str                     # "shop" (shopkeeper-managed) or "user" (self)
    content_types: tuple[str, ...]
    max_bytes: int


def _category(name: str, prefix: str, scope: str, ctypes: tuple[str, ...], cap: int) -> MediaCategory:
    return MediaCategory(name=name, prefix=prefix, scope=scope, content_types=ctypes, max_bytes=cap)


MEDIA_CATEGORIES: dict[str, MediaCategory] = {
    "PRODUCT_IMAGE": _category(
        "PRODUCT_IMAGE", "products", "shop",
        ("image/jpeg", "image/png", "image/webp"),
        settings.MEDIA_MAX_IMAGE_BYTES,
    ),
    "SHOP_IMAGE": _category(
        "SHOP_IMAGE", "shops", "shop",
        ("image/jpeg", "image/png", "image/webp"),
        settings.MEDIA_MAX_IMAGE_BYTES,
    ),
    "DOCUMENT": _category(
        "DOCUMENT", "documents", "user",
        ("application/pdf",),
        settings.MEDIA_MAX_DOCUMENT_BYTES,
    ),
    # Support screenshots — evidence a shopkeeper attaches to a support ticket
    # from *Report an issue*. SELF-scoped (``user``): a ticket belongs to its
    # reporter, and the shop association on a ticket is optional by design, so
    # the key is scoped to the reporter's own id rather than to a shop. A key
    # minted for user A can therefore never be attached to user B's ticket.
    # Images only — the report screen offers "attach a screenshot".
    "SUPPORT_ATTACHMENT": _category(
        "SUPPORT_ATTACHMENT", "support", "user",
        ("image/jpeg", "image/png", "image/webp"),
        settings.MEDIA_MAX_IMAGE_BYTES,
    ),
}

# Server-minted key shape: {prefix}/{scope}/{YYYY}/{MM}/{uuid8}_{safe}.{ext}
_KEY_RE = re.compile(
    r"^(?P<prefix>(?:products|shops|documents|support))"
    r"/(?P<scope>\d+)"
    r"/(?P<year>20\d{2})/(?P<month>0[1-9]|1[0-2])"
    r"/[0-9a-f]{8}_[A-Za-z0-9._-]+\.(?:jpg|jpeg|png|webp|pdf)$"
)


@dataclass
class ParsedKey:
    category: MediaCategory
    scope_value: int


def parse_object_key(key: str) -> ParsedKey:
    """Validate an untrusted object key against the server-minted shape.

    Rejects traversal (``..``), foreign prefixes, and malformed segments —
    callers can trust ``scope_value`` enough to run authorization on it.
    """
    if not key or ".." in key or not _KEY_RE.match(key):
        raise ValidationError("Invalid object key", data={"reason_code": "INVALID_KEY"})
    prefix = key.split("/", 1)[0]
    category = next(c for c in MEDIA_CATEGORIES.values() if c.prefix == prefix)
    return ParsedKey(category=category, scope_value=int(key.split("/")[1]))


def _extensions(category: MediaCategory) -> tuple[str, ...]:
    return tuple(ext for ct in category.content_types for ext in MEDIA_TYPES.get(ct, ()))


# ── Authorization ────────────────────────────────────────────────────────────


def _authorize_scope(db: Session, user: User, category: MediaCategory, scope_value: int) -> None:
    """Enforce access control for a shop- or user-scoped object."""
    if category.scope == "shop":
        # resolve_shop_access: active owner/manager or admin — 403/404 otherwise.
        shopkeeper_service.resolve_shop_access(db, user, scope_value)
        return
    # user-scoped (documents): owner or admin only.
    role_name = user.role.name if user.role is not None else ""
    if role_name != "admin" and user.id != scope_value:
        raise ForbiddenError("You do not have access to this object")



def _authorize_read(db: Session, user: User, category: MediaCategory, scope_value: int) -> None:
    """Enforce READ access (Phase 7 integration).

    Catalog media (PRODUCT_IMAGE / SHOP_IMAGE) is customer-visible content —
    any authenticated user may obtain a presigned read URL for display.
    Documents stay strictly owner/admin. Write paths are never relaxed here.
    """
    if category.scope == "user":
        _authorize_scope(db, user, category, scope_value)
    # shop-scoped catalog media: an authenticated caller is sufficient.


def _resolve_scope(db: Session, user: User, category: MediaCategory, shop_id: Optional[int]) -> int:
    """Resolve the scope value embedded in the key, checking authorization."""
    if category.scope == "shop":
        if shop_id is None:
            raise ValidationError("shop_id is required for this media category")
        # Raises NotFoundError/ForbiddenError for non-associated callers.
        access = shopkeeper_service.resolve_shop_access(db, user, shop_id)
        return access.shop.id
    if shop_id is not None and shop_id != user.id:
        # Documents are strictly self-scoped; admins may not impersonate either.
        raise ForbiddenError("Documents can only be uploaded for yourself")
    return user.id


def _category_or_error(category_name: str) -> MediaCategory:
    category = MEDIA_CATEGORIES.get(str(category_name or "").upper())
    if category is None:
        raise ValidationError(
            "Unknown media category",
            data={"allowed": sorted(MEDIA_CATEGORIES)},
        )
    return category


def _declared_extension(filename: str, category: MediaCategory) -> str:
    lower = filename.lower()
    for ext in _extensions(category):
        if lower.endswith(ext):
            return ext
    raise ValidationError(
        f"Only {'/'.join(_extensions(category))} files are supported",
        data={"reason_code": "INVALID_FILE_TYPE"},
    )


def _provider() -> Any:
    """Storage provider singleton — construction failures become typed 503s."""
    try:
        return get_storage()
    except Exception as exc:  # noqa: BLE001 — config/provider construction
        raise StorageUnavailableError(f"Storage provider unavailable: {exc}") from exc


def _provider_for_media() -> Any:
    """Provider that must support the signed-upload / HEAD interface.

    Providers without signed-upload support (e.g. Cloudinary) fail closed as
    a typed 503 instead of leaking a 500 NotImplementedError.
    """
    provider = _provider()
    if (
        getattr(type(provider), "create_signed_upload", None)
        is BaseStorageProvider.create_signed_upload
        or not hasattr(type(provider), "create_signed_upload")
    ):
        raise StorageUnavailableError(
            "This storage provider does not support signed uploads — configure STORAGE_PROVIDER=s3"
        )
    return provider


# ── Upload flows ─────────────────────────────────────────────────────────────


async def create_upload_intent(
    db: Session,
    user: User,
    *,
    category_name: str,
    filename: str,
    content_type: str,
    size_bytes: int,
    shop_id: Optional[int] = None,
) -> dict[str, Any]:
    """Authorize + validate an upload request, then mint a signed upload grant.

    The grant is a presigned POST policy whose conditions pin the exact key,
    the exact content type, and the category size cap — S3 itself rejects
    anything else, even with a valid signature.
    """
    category = _category_or_error(category_name)

    # Authorization FIRST — nothing else leaks before access is proven.
    scope_value = _resolve_scope(db, user, category, shop_id)

    safe_name = str(filename or "").strip()
    if not safe_name:
        raise ValidationError("filename is required", data={"reason_code": "EMPTY_FILE"})
    ext = _declared_extension(safe_name, category)
    if content_type not in category.content_types:
        raise ValidationError(
            f"content_type must be one of {', '.join(category.content_types)}",
            data={"reason_code": "CONTENT_TYPE_NOT_ALLOWED"},
        )
    if not isinstance(size_bytes, int) or size_bytes < 1:
        raise ValidationError("size_bytes must be a positive integer")
    if size_bytes > category.max_bytes:
        raise ValidationError(
            f"File exceeds the {category.max_bytes // (1024 * 1024)} MB limit",
            data={"reason_code": "FILE_TOO_LARGE", "max_bytes": category.max_bytes},
        )

    folder = f"{category.prefix}/{scope_value}"
    key = build_object_key(folder, safe_name)
    if not key.endswith(ext):
        # Keep the declared (validated) extension authoritative.
        key = key.rsplit(".", 1)[0] + ext

    grant = await _provider_for_media().create_signed_upload(
        key=key,
        content_type=content_type,
        max_bytes=category.max_bytes,
    )
    grant["category"] = category.name
    grant["filename"] = safe_name
    logger.info(
        "media upload intent user=%s category=%s key=%s size=%s",
        user.id, category.name, key, size_bytes,
    )
    return grant

async def direct_upload(
    db: Session,
    user: User,
    *,
    category_name: str,
    filename: str,
    content: bytes,
    shop_id: Optional[int] = None,
) -> dict[str, Any]:
    """Backend-streamed upload (local-disk provider / development only).

    Full in-process validation: extension, magic-byte truth, size cap — then
    stored under the same key strategy as the signed flow. Production clients
    must use the signed-URL flow instead.
    """
    category = _category_or_error(category_name)
    scope_value = _resolve_scope(db, user, category, shop_id)

    try:
        safe_name, detected_type = validate_media_upload(
            filename,
            content,
            allowed_content_types=category.content_types,
            max_bytes=category.max_bytes,
        )
    except ValueError as exc:
        reason = getattr(exc, "reason_code", "INVALID_FILE")
        raise ValidationError(str(exc), data={"reason_code": reason}) from exc

    provider = _provider_for_media()
    if getattr(provider, "upload_dir", None) is None:
        raise ValidationError(
            "Direct upload is only available in local development — use the signed upload URL",
            data={"reason_code": "SIGNED_UPLOAD_REQUIRED"},
        )

    ext = MEDIA_TYPES[detected_type][0]
    key = build_object_key(f"{category.prefix}/{scope_value}", safe_name)
    key = key.rsplit(".", 1)[0] + ext

    _persist_local(provider, key, content)
    logger.info("media direct upload user=%s key=%s bytes=%s", user.id, key, len(content))
    return {"key": key, "content_type": detected_type, "size": len(content), "category": category.name}


def _persist_local(provider: Any, key: str, content: bytes) -> None:
    """Write bytes at the exact server-minted key (local provider only)."""
    from pathlib import Path as _Path

    path = _Path(provider.upload_dir) / key
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content)


def _is_s3(provider: Any) -> bool:
    return getattr(provider, "client", None) is not None and getattr(provider, "upload_dir", None) is None


# ── Confirm / read / delete ──────────────────────────────────────────────────


async def confirm_upload(db: Session, user: User, key: str) -> dict[str, Any]:
    """Verify a signed upload actually landed — then return a read URL.

    Re-checks content-type and size AT the object store so the policy
    conditions are the first line of defense and the backend the second.
    """
    parsed = parse_object_key(key)
    _authorize_scope(db, user, parsed.category, parsed.scope_value)

    provider = _provider_for_media()
    head = await provider.get_object_head(key)
    if head is None:
        raise NotFoundError(
            "Upload not found — the object was never uploaded, already deleted, or the signed URL expired"
        )
    stored_type = str(head.get("content_type") or "").split(";")[0].strip()
    if stored_type and stored_type not in parsed.category.content_types:
        raise ValidationError(
            "Stored object has an unexpected content type",
            data={"reason_code": "CONTENT_TYPE_NOT_ALLOWED"},
        )
    if head.get("size", 0) > parsed.category.max_bytes:
        raise ValidationError(
            "Stored object exceeds the size limit",
            data={"reason_code": "FILE_TOO_LARGE"},
        )
    url = await provider.get_file_url(key)
    return {
        "key": key,
        "url": url,
        "size": head.get("size"),
        "content_type": stored_type or None,
        "category": parsed.category.name,
    }


async def get_media_url(db: Session, user: User, key: str) -> dict[str, Any]:
    """Authorized read access — short-lived presigned GET for private objects."""
    parsed = parse_object_key(key)
    _authorize_read(db, user, parsed.category, parsed.scope_value)
    url = await _provider_for_media().get_file_url(key)
    return {"key": key, "url": url, "category": parsed.category.name}

async def attach_media(
    db: Session,
    user: User,
    *,
    key: str,
    expected_category: str,
    shop_id: Optional[int] = None,
) -> dict[str, Any]:
    """Validate an uploaded object key and authorize attaching it to a record.

    Phase 7 product/shop integration entry point. Enforces:
      * key shape       - server-minted ``{prefix}/{scope}/...`` only
      * category match  - e.g. a DOCUMENT key can never become a product image
      * scope match     - a key minted for shop A can never be attached to
                          shop B (cross-tenant object borrowing)
      * existence       - the object must actually be uploaded (HEAD), so
                          phantom keys cannot be referenced
    Returns the durable ``storage_ref`` (``s3://{bucket}/{key}``) to store in
    DB columns plus a short-lived presigned URL for immediate use, and the
    SERVER-OBSERVED ``size_bytes`` / ``content_type`` from the HEAD — callers
    that persist evidence (support screenshots) record what the object really
    is, never what the client claimed.
    """
    parsed = parse_object_key(key)
    if parsed.category.name != expected_category:
        raise ValidationError(
            f"Object is a {parsed.category.name}, not a {expected_category}",
            data={"reason_code": "CATEGORY_MISMATCH", "expected": expected_category},
        )
    # Authorization on the key's own scope (owner/manager/admin or self).
    _authorize_scope(db, user, parsed.category, parsed.scope_value)
    if shop_id is not None and parsed.scope_value != shop_id:
        raise ForbiddenError("Object belongs to a different shop")

    provider = _provider_for_media()
    head = await provider.get_object_head(key)
    if head is None:
        raise NotFoundError(
            "Object not found - upload and confirm the file before attaching it"
        )
    url = await provider.get_file_url(key)
    if _is_s3(provider):
        storage_ref = f"s3://{provider.bucket}/{key}"
    else:
        storage_ref = key
    logger.info(
        "media attached user=%s key=%s category=%s scope=%s",
        user.id, key, parsed.category.name, parsed.scope_value,
    )
    return {
        "key": key,
        "storage_ref": storage_ref,
        "url": url,
        "category": parsed.category.name,
        "size_bytes": head.get("size"),
        "content_type": head.get("content_type"),
    }


async def delete_media(db: Session, user: User, key: str) -> dict[str, Any]:
    """Owner/manager/admin deletion — authorization before any mutation."""
    parsed = parse_object_key(key)
    _authorize_scope(db, user, parsed.category, parsed.scope_value)

    provider = _provider_for_media()
    if _is_s3(provider):
        # Verify existence first so deleting an absent object is a 404,
        # not a silent success (S3 delete_object is idempotent by design).
        if await provider.get_object_head(key) is None:
            raise NotFoundError("Object not found")
        try:
            provider.client.delete_object(Bucket=provider.bucket, Key=key)
        except Exception as exc:  # noqa: BLE001
            logger.warning("S3 delete failed for %s: %s", key, exc)
            raise StorageUnavailableError(
                "Could not delete the object; please retry"
            ) from exc
    else:
        from pathlib import Path as _Path

        path = _Path(provider.upload_dir) / key
        if not path.is_file():
            raise NotFoundError("Object not found")
        try:
            path.unlink()
        except OSError as exc:
            logger.warning("Local delete failed for %s: %s", key, exc)
            raise StorageUnavailableError(
                "Could not delete the object; please retry"
            ) from exc

    logger.info("media deleted user=%s key=%s", user.id, key)
    return {"key": key, "deleted": True}


# ── Attach to product / shop records (Phase 7 integration) ──────────────────
#
# The client uploads via the signed flow, then attaches the returned key to a
# product or shop record. Only server-minted keys scoped to the caller's own
# shop are accepted, and the object must exist (HEAD) at attach time.
#
# Read strategy: DB stores the KEY (never a presigned URL — those expire);
# ``resolve_media_url`` presigns at serialization time.


async def attach_to_product(
    db: Session,
    user: User,
    *,
    shop_id: int,
    product_master_id: int,
    key: str,
) -> dict[str, Any]:
    """Attach an uploaded PRODUCT_IMAGE key as an image of the shop's product."""
    from app.models.product import ProductImage, ProductMaster

    access = shopkeeper_service.resolve_shop_access(db, user, shop_id)
    access.require("product", "update")

    parsed = parse_object_key(key)
    if parsed.category.name != "PRODUCT_IMAGE" or parsed.scope_value != shop_id:
        raise ForbiddenError("Key does not belong to this shop's product images")

    master = (
        db.query(ProductMaster)
        .filter(ProductMaster.id == product_master_id, ProductMaster.is_deleted == False)  # noqa: E712
        .first()
    )
    if master is None:
        raise NotFoundError("Product not found")

    provider = _provider_for_media()
    head = await provider.get_object_head(key)
    if head is None:
        raise NotFoundError("Upload not found — complete the upload before attaching")

    existing = (
        db.query(ProductImage)
        .filter(ProductImage.product_master_id == product_master_id)
        .count()
    )
    image = ProductImage(
        product_master_id=product_master_id,
        image_url=key,
        is_primary=existing == 0,
        sort_order=existing,
    )
    db.add(image)
    db.flush()
    logger.info(
        "media attached product=%s shop=%s key=%s", product_master_id, shop_id, key
    )
    return {
        "key": key,
        "product_master_id": product_master_id,
        "image_id": image.id,
        "is_primary": image.is_primary,
        "url": await provider.get_file_url(key),
    }


async def attach_to_shop(
    db: Session,
    user: User,
    *,
    shop_id: int,
    key: str,
    field: str = "image",
) -> dict[str, Any]:
    """Attach an uploaded SHOP_IMAGE key as the shop's image/cover/logo."""
    from app.models.shop import Shop

    access = shopkeeper_service.resolve_shop_access(db, user, shop_id)
    access.require("shop", "update")

    parsed = parse_object_key(key)
    if parsed.category.name != "SHOP_IMAGE" or parsed.scope_value != shop_id:
        raise ForbiddenError("Key does not belong to this shop's images")

    column = {"image": "image_url", "cover": "cover_image_url", "logo": "logo_url"}.get(field)
    if column is None:
        raise ValidationError("field must be one of: image, cover, logo")

    shop = db.query(Shop).filter(Shop.id == shop_id, Shop.is_deleted == False).first()  # noqa: E712
    if shop is None:
        raise NotFoundError("Shop not found")

    provider = _provider_for_media()
    head = await provider.get_object_head(key)
    if head is None:
        raise NotFoundError("Upload not found — complete the upload before attaching")

    setattr(shop, column, key)
    db.flush()
    logger.info("media attached shop=%s field=%s key=%s", shop_id, field, key)
    return {
        "key": key,
        "shop_id": shop_id,
        "field": column,
        "url": await provider.get_file_url(key),
    }


def resolve_media_url(value: Optional[str]) -> Optional[str]:
    """Presign a stored media key for display; pass legacy URLs through.

    DB columns hold server-minted keys (e.g. ``products/12/2026/08/ab12cd34_
    photo.jpg``). At serialization time they are exchanged for short-lived
    presigned GETs. Any other value (absolute https URL, seed placeholder,
    empty) is returned unchanged. On a storage outage the raw value is
    returned so catalog reads degrade gracefully instead of failing.
    """
    if not value:
        return value
    try:
        parse_object_key(value)
    except ValidationError:
        return value  # legacy/external URL — not a media key
    try:
        return get_storage().presign_get_sync(value)
    except Exception as exc:  # noqa: BLE001 — degrade gracefully
        logger.warning("media presign failed for %s: %s", value, exc)
        return value
