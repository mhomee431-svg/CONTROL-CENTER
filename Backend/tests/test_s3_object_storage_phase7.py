"""Phase 7 — S3 object storage tests.

Coverage map (mirrors the phase checklist):
    * upload        — signed POST grant (service + boto3 policy), direct upload
    * retrieve      — authorized presigned GET, confirm → read URL
    * invalid file  — wrong extension / content-type / magic bytes
    * oversized     — declared size over the cap, stored object over the cap
    * unauthorized  — no token, stranger on shop scope, foreign documents
    * delete        — owner ok, missing 404, stranger 403, backend failure 503
    * failure rec.  — storage outages → typed 503 STORAGE_UNAVAILABLE
"""

import os
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import create_engine  # noqa: E402
from sqlalchemy.orm import sessionmaker  # noqa: E402
from sqlalchemy.pool import StaticPool  # noqa: E402

from app.core.config import settings  # noqa: E402

settings.RATE_LIMIT_ENABLED = False

from app.core.exceptions import (  # noqa: E402
    ForbiddenError,
    NotFoundError,
    ValidationError,
)
from app.core.storage import (  # noqa: E402
    BaseStorageProvider,
    StorageUnavailableError,
    build_object_key,
)
from app.core.upload_security import (  # noqa: E402
    sniff_media_content_type,
    validate_media_upload,
)
from datetime import datetime  # noqa: E402

from app.models.base import Base  # noqa: E402
from app.models.inventory_import import InventoryImportJob, InventoryImportRow  # noqa: E402
from app.models.role import Permission, Role, role_permissions  # noqa: E402
from app.models.shop import Shop, ShopManager, ShopOwner  # noqa: E402
from app.models.user import User, UserStatus  # noqa: E402
from app.services import media_service  # noqa: E402

# Adapt PostGIS Geography columns for plain SQLite (shared helper).
from tests.geo_compat import strip_geo_columns  # noqa: E402

strip_geo_columns()


def _portable_timestamp_defaults():
    """Replace Postgres ``now()`` server defaults with Python-side defaults
    (same pattern as the phase 30 tests — required for SQLite)."""
    from sqlalchemy import ColumnDefault

    def _now(ctx=None):
        return datetime.utcnow()

    for table in Base.metadata.tables.values():
        for col in table.columns:
            sd = getattr(col, "server_default", None)
            sd_arg = getattr(sd, "arg", None)
            if isinstance(sd_arg, str) and sd_arg.lower() == "now()":
                if col.default is None:
                    col.default = ColumnDefault(_now)
                col.server_default = None
            elif isinstance(sd_arg, str) and sd_arg.lower() == "false":
                if col.default is None and (
                    getattr(getattr(col.type, "python_type", None), "__name__", "") == "bool"
                ):
                    col.default = ColumnDefault(False)
                col.server_default = None
            ou = getattr(col, "onupdate", None)
            ou_arg = getattr(ou, "arg", None)
            if ou is not None and str(ou_arg).strip().lower().startswith("now"):
                col.onupdate = ColumnDefault(_now, for_update=True)


_portable_timestamp_defaults()

PNG_BYTES = b"\x89PNG\r\n\x1a\n" + b"\x00" * 64
JPEG_BYTES = b"\xff\xd8\xff\xe0" + b"\x00" * 64
WEBP_BYTES = b"RIFF\x24\x00\x00\x00WEBPVP8 " + b"\x00" * 32
PDF_BYTES = b"%PDF-1.7\n" + b"\x00" * 64
EXE_BYTES = b"MZ\x90\x00\x03\x00\x00\x00" + b"\x00" * 64

TABLES = [
    Role.__table__,
    Permission.__table__,
    role_permissions,
    User.__table__,
    Shop.__table__,
    ShopOwner.__table__,
    ShopManager.__table__,
    InventoryImportJob.__table__,
    InventoryImportRow.__table__,
]


@pytest.fixture()
def db():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine, tables=TABLES)
    session = sessionmaker(bind=engine)()
    yield session
    session.close()
    engine.dispose()


# ── Entity factories (same pattern as phase 30 tests) ────────────────────────
_counter = {"n": 0}


def _next_id():
    _counter["n"] += 1
    return _counter["n"]


def make_user(db, role_name="customer"):
    n = _next_id()
    role = db.query(Role).filter(Role.name == role_name).first()
    if role is None:
        role = Role(name=role_name, description=role_name)
        db.add(role)
        db.flush()
    user = User(
        phone_number=f"+9198765{n:05d}",
        name=f"User {n}",
        role_id=role.id,
        status=UserStatus.ACTIVE,
        is_active=True,
    )
    db.add(user)
    db.flush()
    return user


def make_shop(db, owner=None):
    from app.models.shop import ShopStatus

    n = _next_id()
    shop = Shop(
        name=f"Shop {n}",
        description=f"desc {n}",
        status=ShopStatus.ACTIVE,
        latitude=25.59,
        longitude=85.13,
    )
    db.add(shop)
    db.flush()
    if owner is not None:
        db.add(ShopOwner(shop_id=shop.id, user_id=owner.id, is_active=True))
        db.flush()
    return shop


class FakeBotoError(Exception):
    """Mimics botocore ClientError shape (response dict with Error.Code)."""

    def __init__(self, code, status):
        self.response = {"Error": {"Code": code}, "ResponseMetadata": {"HTTPStatusCode": status}}
        super().__init__(code)


class FakeS3Client:
    """Dict-backed stand-in for the boto3 S3 client (no network)."""

    def __init__(self, fail_actions=None):
        self.objects = {}
        self.fail_actions = fail_actions or set()
        self.deleted = []

    def generate_presigned_post(self, Bucket, Key, Conditions, ExpiresIn):
        if "signed-upload" in self.fail_actions:
            raise ConnectionError("endpoint down")
        self.last_conditions = Conditions
        return {"url": f"https://{Bucket}.s3.test.amazonaws.com/", "fields": {"key": Key, "policy": "b64"}}

    def generate_presigned_url(self, ClientMethod, Params, ExpiresIn):
        if "presign" in self.fail_actions:
            raise ConnectionError("endpoint down")
        return f"https://s3.test/{Params['Bucket']}/{Params['Key']}?sig=abc&exp={ExpiresIn}"

    def head_object(self, Bucket, Key):
        if "head" in self.fail_actions:
            raise ConnectionError("endpoint down")
        obj = self.objects.get(Key)
        if obj is None:
            raise FakeBotoError("404", 404)
        return {"ContentLength": obj["size"], "ContentType": obj["content_type"]}

    def delete_object(self, Bucket, Key):
        if "delete" in self.fail_actions:
            raise ConnectionError("endpoint down")
        self.objects.pop(Key, None)
        self.deleted.append(Key)

    def put(self, key, content, content_type):
        self.objects[key] = {"size": len(content), "content_type": content_type}


class FakeS3Provider:
    """Same interface as S3StorageProvider but backed by FakeS3Client."""

    def __init__(self, client=None):
        self.bucket = "test-bucket"
        self.client = client or FakeS3Client()

    async def create_signed_upload(self, key, content_type, max_bytes, expires_in=None):
        conditions = [
            {"bucket": self.bucket},
            ["content-length-range", 1, max_bytes],
            {"key": key},
            {"Content-Type": content_type},
        ]
        post = self.client.generate_presigned_post(self.bucket, key, conditions, expires_in or 600)
        return {
            "mode": "post",
            "url": post["url"],
            "fields": post["fields"],
            "key": key,
            "expires_in": expires_in or 600,
            "content_type": content_type,
            "max_bytes": max_bytes,
        }

    async def get_object_head(self, key):
        try:
            head = self.client.head_object(self.bucket, key)
        except FakeBotoError:
            return None
        except Exception as exc:  # noqa: BLE001
            raise StorageUnavailableError(f"Storage head failed: {exc}") from exc
        return {"size": head["ContentLength"], "content_type": head["ContentType"]}

    async def get_file_url(self, key):
        return self.client.generate_presigned_url("get_object", {"Bucket": self.bucket, "Key": key}, 900)


# The real provider methods (and therefore media_service functions) are async;
# expose sync wrappers on the module so tests stay simple and synchronous.
import asyncio  # noqa: E402

for _name in ("create_upload_intent", "direct_upload", "confirm_upload", "get_media_url", "delete_media"):
    _orig = getattr(media_service, _name)

    def _make(orig):
        def wrapper(*args, **kwargs):
            return asyncio.run(orig(*args, **kwargs))
        return wrapper

    setattr(media_service, _name, _make(_orig))


@pytest.fixture()
def fake_s3(monkeypatch):
    provider = FakeS3Provider()
    monkeypatch.setattr(media_service, "get_storage", lambda: provider)
    return provider


# ── Validation unit tests ────────────────────────────────────────────────────


class TestFileValidation:
    def test_sniff_detects_real_types(self):
        assert sniff_media_content_type(PNG_BYTES) == "image/png"
        assert sniff_media_content_type(JPEG_BYTES) == "image/jpeg"
        assert sniff_media_content_type(WEBP_BYTES) == "image/webp"
        assert sniff_media_content_type(PDF_BYTES) == "application/pdf"

    def test_sniff_rejects_exe_masquerading_as_image(self):
        assert sniff_media_content_type(EXE_BYTES) is None

    def test_validate_rejects_disallowed_extension(self):
        with pytest.raises(ValueError) as exc:
            validate_media_upload(
                "shell.php", PNG_BYTES,
                allowed_content_types=("image/png",),
                max_bytes=1024,
            )
        assert exc.value.reason_code == "INVALID_FILE_TYPE"

    def test_validate_rejects_unrecognized_content(self):
        with pytest.raises(ValueError) as exc:
            validate_media_upload(
                "a.png", EXE_BYTES,
                allowed_content_types=("image/png",),
                max_bytes=1024,
            )
        assert exc.value.reason_code == "CONTENT_TYPE_MISMATCH"

    def test_validate_rejects_content_not_in_allowlist(self):
        # Valid extension for the allow-list, but the sniffed bytes are
        # actually JPEG — declared-type forgery must be rejected.
        with pytest.raises(ValueError) as exc:
            validate_media_upload(
                "a.png", JPEG_BYTES,
                allowed_content_types=("image/png",),
                max_bytes=1024,
            )
        assert exc.value.reason_code == "CONTENT_TYPE_NOT_ALLOWED"

    def test_validate_rejects_oversized(self):
        big = PNG_BYTES + b"\x00" * 2048
        with pytest.raises(ValueError) as exc:
            validate_media_upload(
                "big.png", big,
                allowed_content_types=("image/png",),
                max_bytes=1024,
            )
        assert exc.value.reason_code == "FILE_TOO_LARGE"

    def test_validate_rejects_empty_file(self):
        # Empty bytes fail the sniff before the empty check fires.
        with pytest.raises(ValueError) as exc:
            validate_media_upload(
                "empty.png", b"",
                allowed_content_types=("image/png",),
                max_bytes=1024,
            )
        assert exc.value.reason_code == "CONTENT_TYPE_MISMATCH"

    def test_validate_sanitizes_traversal_filename(self):
        safe, _ = validate_media_upload(
            "../../etc/passwd.png", PNG_BYTES,
            allowed_content_types=("image/png",),
            max_bytes=1024,
        )
        assert "/" not in safe and ".." not in safe

    def test_validate_accepts_valid_png(self):
        safe, ctype = validate_media_upload(
            "photo.PNG", PNG_BYTES,
            allowed_content_types=("image/png",),
            max_bytes=1024,
        )
        assert ctype == "image/png"
        assert safe.lower().endswith(".png")


# ── Key strategy ─────────────────────────────────────────────────────────────


class TestKeyStrategy:
    def test_key_shape(self):
        key = build_object_key("products/12", "My Photo.png")
        parts = key.split("/")
        assert parts[0] == "products" and parts[1] == "12"
        assert len(parts) == 5 and parts[2].isdigit() and parts[3].isdigit()
        assert parts[4].endswith(".png") and ".." not in key

    def test_parse_accepts_minted_key(self, fake_s3):
        key = build_object_key("products/12", "photo.png")
        parsed = media_service.parse_object_key(key)
        assert parsed.category.name == "PRODUCT_IMAGE"
        assert parsed.scope_value == 12

    def test_parse_rejects_traversal_and_foreign_prefix(self, fake_s3):
        for bad in ("../secret.png", "backups/db.sql", "products/../../x.png", "products/12/x.exe"):
            with pytest.raises(ValidationError):
                media_service.parse_object_key(bad)

    def test_category_registry(self):
        assert media_service.MEDIA_CATEGORIES["PRODUCT_IMAGE"].max_bytes == 5 * 1024 * 1024
        assert media_service.MEDIA_CATEGORIES["DOCUMENT"].max_bytes == 15 * 1024 * 1024
        assert media_service.MEDIA_CATEGORIES["PRODUCT_IMAGE"].scope == "shop"
        assert media_service.MEDIA_CATEGORIES["DOCUMENT"].scope == "user"


# ── Signed upload flow ───────────────────────────────────────────────────────


class TestSignedUploadFlow:
    def test_upload_intent_returns_signed_post(self, db, fake_s3):
        owner = make_user(db, "shopkeeper")
        shop = make_shop(db, owner)
        db.commit()
        grant = media_service.create_upload_intent(
            db, owner,
            category_name="PRODUCT_IMAGE",
            filename="product.jpg",
            content_type="image/jpeg",
            size_bytes=2048,
            shop_id=shop.id,
        )
        assert grant["mode"] == "post"
        assert grant["fields"]["key"].startswith(f"products/{shop.id}/")
        assert "policy" in grant["fields"]
        assert grant["max_bytes"] == 5 * 1024 * 1024

    def test_policy_conditions_bind_key_type_and_size(self, db, fake_s3):
        owner = make_user(db, "shopkeeper")
        shop = make_shop(db, owner)
        db.commit()
        media_service.create_upload_intent(
            db, owner,
            category_name="PRODUCT_IMAGE",
            filename="p.png",
            content_type="image/png",
            size_bytes=100,
            shop_id=shop.id,
        )
        conditions = fake_s3.client.last_conditions
        assert ["content-length-range", 1, 5 * 1024 * 1024] in conditions
        assert {"Content-Type": "image/png"} in conditions

    def test_oversized_declared_size_rejected(self, db, fake_s3):
        owner = make_user(db, "shopkeeper")
        shop = make_shop(db, owner)
        db.commit()
        with pytest.raises(ValidationError) as exc:
            media_service.create_upload_intent(
                db, owner,
                category_name="PRODUCT_IMAGE",
                filename="huge.png",
                content_type="image/png",
                size_bytes=6 * 1024 * 1024,
                shop_id=shop.id,
            )
        assert exc.value.data["reason_code"] == "FILE_TOO_LARGE"

    def test_document_cap_is_15mb(self, db, fake_s3):
        user = make_user(db)
        db.commit()
        with pytest.raises(ValidationError) as exc:
            media_service.create_upload_intent(
                db, user,
                category_name="DOCUMENT",
                filename="doc.pdf",
                content_type="application/pdf",
                size_bytes=16 * 1024 * 1024,
            )
        assert exc.value.data["reason_code"] == "FILE_TOO_LARGE"

    def test_content_type_not_in_allowlist_rejected(self, db, fake_s3):
        owner = make_user(db, "shopkeeper")
        shop = make_shop(db, owner)
        db.commit()
        with pytest.raises(ValidationError) as exc:
            media_service.create_upload_intent(
                db, owner,
                category_name="PRODUCT_IMAGE",
                filename="movie.mp4",
                content_type="video/mp4",
                size_bytes=100,
                shop_id=shop.id,
            )
        assert exc.value.data["reason_code"] == "INVALID_FILE_TYPE"

    def test_unknown_category_rejected(self, db, fake_s3):
        user = make_user(db)
        db.commit()
        with pytest.raises(ValidationError):
            media_service.create_upload_intent(
                db, user,
                category_name="BACKUP_DUMP",
                filename="db.sql",
                content_type="application/sql",
                size_bytes=10,
            )


# ── Confirm + retrieve ───────────────────────────────────────────────────────


class TestConfirmAndRetrieve:
    def _upload(self, db, fake_s3, owner, shop):
        grant = media_service.create_upload_intent(
            db, owner,
            category_name="PRODUCT_IMAGE",
            filename="photo.png",
            content_type="image/png",
            size_bytes=len(PNG_BYTES),
            shop_id=shop.id,
        )
        key = grant["key"]
        fake_s3.client.put(key, PNG_BYTES, "image/png")
        return key

    def test_confirm_returns_read_url(self, db, fake_s3):
        owner = make_user(db, "shopkeeper")
        shop = make_shop(db, owner)
        db.commit()
        key = self._upload(db, fake_s3, owner, shop)
        result = media_service.confirm_upload(db, owner, key)
        assert result["url"].startswith("https://s3.test/")
        assert result["content_type"] == "image/png"
        assert result["size"] == len(PNG_BYTES)

    def test_confirm_missing_object_is_404(self, db, fake_s3):
        owner = make_user(db, "shopkeeper")
        shop = make_shop(db, owner)
        db.commit()
        grant = media_service.create_upload_intent(
            db, owner,
            category_name="PRODUCT_IMAGE",
            filename="photo.png",
            content_type="image/png",
            size_bytes=10,
            shop_id=shop.id,
        )
        with pytest.raises(NotFoundError):
            media_service.confirm_upload(db, owner, grant["key"])

    def test_confirm_stored_object_over_cap_rejected(self, db, fake_s3):
        owner = make_user(db, "shopkeeper")
        shop = make_shop(db, owner)
        db.commit()
        grant = media_service.create_upload_intent(
            db, owner,
            category_name="PRODUCT_IMAGE",
            filename="photo.png",
            content_type="image/png",
            size_bytes=10,
            shop_id=shop.id,
        )
        key = grant["key"]
        fake_s3.client.put(key, PNG_BYTES + b"\x00" * (6 * 1024 * 1024), "image/png")
        with pytest.raises(ValidationError) as exc:
            media_service.confirm_upload(db, owner, key)
        assert exc.value.data["reason_code"] == "FILE_TOO_LARGE"

    def test_confirm_wrong_stored_content_type_rejected(self, db, fake_s3):
        owner = make_user(db, "shopkeeper")
        shop = make_shop(db, owner)
        db.commit()
        grant = media_service.create_upload_intent(
            db, owner,
            category_name="PRODUCT_IMAGE",
            filename="photo.png",
            content_type="image/png",
            size_bytes=10,
            shop_id=shop.id,
        )
        key = grant["key"]
        fake_s3.client.put(key, EXE_BYTES, "application/x-msdownload")
        with pytest.raises(ValidationError) as exc:
            media_service.confirm_upload(db, owner, key)
        assert exc.value.data["reason_code"] == "CONTENT_TYPE_NOT_ALLOWED"

    def test_get_media_url_authorized(self, db, fake_s3):
        owner = make_user(db, "shopkeeper")
        shop = make_shop(db, owner)
        db.commit()
        key = self._upload(db, fake_s3, owner, shop)
        result = media_service.get_media_url(db, owner, key)
        assert result["url"].startswith("https://s3.test/")

    def test_s3_outage_during_confirm_is_typed_503(self, db, fake_s3):
        owner = make_user(db, "shopkeeper")
        shop = make_shop(db, owner)
        db.commit()
        key = self._upload(db, fake_s3, owner, shop)
        fake_s3.client.fail_actions.add("head")
        with pytest.raises(StorageUnavailableError):
            media_service.confirm_upload(db, owner, key)


# ── Access control ───────────────────────────────────────────────────────────


class TestAccessControl:
    def test_stranger_cannot_upload_to_shop(self, db, fake_s3):
        owner = make_user(db, "shopkeeper")
        shop = make_shop(db, owner)
        stranger = make_user(db, "shopkeeper")
        db.commit()
        with pytest.raises(ForbiddenError):
            media_service.create_upload_intent(
                db, stranger,
                category_name="PRODUCT_IMAGE",
                filename="x.png",
                content_type="image/png",
                size_bytes=100,
                shop_id=shop.id,
            )

    def test_authenticated_user_can_read_catalog_media(self, db, fake_s3):
        """Phase 7 integration contract: catalog media (PRODUCT_IMAGE /
        SHOP_IMAGE) is customer-visible — any *authenticated* user may obtain
        a presigned read URL. Anonymous access is impossible (see
        TestMediaAPI), and write paths remain shop-restricted."""
        owner = make_user(db, "shopkeeper")
        shop = make_shop(db, owner)
        customer = make_user(db, "customer")
        db.commit()
        key = build_object_key(f"products/{shop.id}", "photo.png")
        fake_s3.client.put(key, PNG_BYTES, "image/png")
        result = media_service.get_media_url(db, customer, key)
        assert result["key"] == key
        assert result["url"].startswith("https://")

    def test_stranger_cannot_delete_shop_object(self, db, fake_s3):
        owner = make_user(db, "shopkeeper")
        shop = make_shop(db, owner)
        stranger = make_user(db, "shopkeeper")
        db.commit()
        key = build_object_key(f"shops/{shop.id}", "logo.png")
        fake_s3.client.put(key, PNG_BYTES, "image/png")
        with pytest.raises(ForbiddenError):
            media_service.delete_media(db, stranger, key)

    def test_user_cannot_read_another_users_document(self, db, fake_s3):
        alice = make_user(db)
        bob = make_user(db)
        db.commit()
        key = build_object_key(f"documents/{alice.id}", "id.pdf")
        fake_s3.client.put(key, PDF_BYTES, "application/pdf")
        with pytest.raises(ForbiddenError):
            media_service.get_media_url(db, bob, key)
        with pytest.raises(ForbiddenError):
            media_service.delete_media(db, bob, key)

    def test_document_upload_cannot_impersonate_other_user(self, db, fake_s3):
        alice = make_user(db)
        bob = make_user(db)
        db.commit()
        with pytest.raises(ForbiddenError):
            media_service.create_upload_intent(
                db, alice,
                category_name="DOCUMENT",
                filename="doc.pdf",
                content_type="application/pdf",
                size_bytes=100,
                shop_id=bob.id,
            )

    def test_user_can_read_own_document(self, db, fake_s3):
        alice = make_user(db)
        db.commit()
        key = build_object_key(f"documents/{alice.id}", "id.pdf")
        fake_s3.client.put(key, PDF_BYTES, "application/pdf")
        result = media_service.get_media_url(db, alice, key)
        assert result["url"].startswith("https://s3.test/")

    def test_invalid_keys_never_reach_authorization(self, db, fake_s3):
        user = make_user(db)
        db.commit()
        for bad in ("", "../../x.png", "other/1/2026/01/a.png", "products/abc/2026/01/a.png"):
            with pytest.raises(ValidationError):
                media_service.get_media_url(db, user, bad)


# ── Delete ───────────────────────────────────────────────────────────────────


class TestDelete:
    def test_owner_can_delete(self, db, fake_s3):
        owner = make_user(db, "shopkeeper")
        shop = make_shop(db, owner)
        db.commit()
        key = build_object_key(f"products/{shop.id}", "photo.png")
        fake_s3.client.put(key, PNG_BYTES, "image/png")
        result = media_service.delete_media(db, owner, key)
        assert result["deleted"] is True
        assert key in fake_s3.client.deleted

    def test_delete_missing_object_is_404(self, db, fake_s3):
        owner = make_user(db, "shopkeeper")
        shop = make_shop(db, owner)
        db.commit()
        key = build_object_key(f"products/{shop.id}", "ghost.png")
        with pytest.raises(NotFoundError):
            media_service.delete_media(db, owner, key)

    def test_delete_backend_failure_is_typed_503(self, db, fake_s3):
        owner = make_user(db, "shopkeeper")
        shop = make_shop(db, owner)
        db.commit()
        key = build_object_key(f"products/{shop.id}", "photo.png")
        fake_s3.client.put(key, PNG_BYTES, "image/png")
        fake_s3.client.fail_actions.add("delete")
        with pytest.raises(StorageUnavailableError):
            media_service.delete_media(db, owner, key)
        # Object must remain intact for retry (failure recovery).
        assert key in fake_s3.client.objects

    def test_head_failure_before_delete_is_typed_503(self, db, fake_s3):
        owner = make_user(db, "shopkeeper")
        shop = make_shop(db, owner)
        db.commit()
        key = build_object_key(f"products/{shop.id}", "photo.png")
        fake_s3.client.put(key, PNG_BYTES, "image/png")
        fake_s3.client.fail_actions.add("head")
        with pytest.raises(StorageUnavailableError):
            media_service.delete_media(db, owner, key)


# ── Direct upload (dev provider, full magic-byte validation) ─────────────────


class TestDirectUpload:
    def test_exe_masquerading_as_png_rejected(self, db, fake_s3):
        owner = make_user(db, "shopkeeper")
        shop = make_shop(db, owner)
        db.commit()
        with pytest.raises(ValidationError) as exc:
            media_service.direct_upload(
                db, owner,
                category_name="PRODUCT_IMAGE",
                filename="evil.png",
                content=EXE_BYTES,
                shop_id=shop.id,
            )
        # Exe bytes fail the magic-byte sniff.
        assert exc.value.data["reason_code"] == "CONTENT_TYPE_MISMATCH"

    def test_valid_png_content_detected(self, db, fake_s3):
        owner = make_user(db, "shopkeeper")
        shop = make_shop(db, owner)
        db.commit()
        # Local-disk provider isn't active in tests, but validation must run
        # and pass BEFORE the provider check rejects the storage step.
        with pytest.raises(ValidationError) as exc:
            media_service.direct_upload(
                db, owner,
                category_name="PRODUCT_IMAGE",
                filename="ok.png",
                content=PNG_BYTES,
                shop_id=shop.id,
            )
        # Validation passed; failure is the dev-only storage check.
        assert exc.value.data["reason_code"] == "SIGNED_UPLOAD_REQUIRED"


# ── Failure recovery ─────────────────────────────────────────────────────────


class TestFailureRecovery:
    def test_provider_outage_at_intent_raises(self, db, fake_s3):
        owner = make_user(db, "shopkeeper")
        shop = make_shop(db, owner)
        db.commit()
        fake_s3.client.fail_actions.add("signed-upload")
        with pytest.raises(Exception):
            media_service.create_upload_intent(
                db, owner,
                category_name="PRODUCT_IMAGE",
                filename="x.png",
                content_type="image/png",
                size_bytes=10,
                shop_id=shop.id,
            )

    def test_recover_after_transient_outage(self, db, fake_s3):
        owner = make_user(db, "shopkeeper")
        shop = make_shop(db, owner)
        db.commit()
        fake_s3.client.fail_actions.add("presign")
        with pytest.raises(Exception):
            media_service.get_media_url(db, owner, build_object_key(f"products/{shop.id}", "a.png"))
        fake_s3.client.fail_actions.discard("presign")
        result = media_service.get_media_url(db, owner, build_object_key(f"products/{shop.id}", "a.png"))
        assert result["url"].startswith("https://s3.test/")


# ── API layer (auth required, error envelope) ────────────────────────────────


class TestMediaAPI:
    def test_endpoints_require_authentication(self):
        from app.main import app

        client = TestClient(app, raise_server_exceptions=False)
        for method, path in (
            ("post", "/api/v1/media/upload-url"),
            ("post", "/api/v1/media/confirm"),
            ("get", "/api/v1/media/url"),
            ("delete", "/api/v1/media/objects"),
        ):
            resp = getattr(client, method)(path, **({"json": {}} if method == "post" else {}))
            assert resp.status_code == 401, f"{method} {path} -> {resp.status_code}"

class TestProviderCapability:
    def test_unsupported_provider_fails_closed_as_503(self, db, monkeypatch):
        """A provider without signed-upload support (e.g. Cloudinary) must
        surface a typed STORAGE_UNAVAILABLE 503 — never an untyped 500."""
        class CloudinaryLike(BaseStorageProvider):
            """Mimics CloudinaryStorageProvider: inherits the base's raising
            create_signed_upload/get_object_head without overriding them."""

            async def upload_file(self, *a, **k):
                return "u"
            async def delete_file(self, *a, **k):
                return True
            async def get_file_url(self, *a, **k):
                return "u"

        monkeypatch.setattr(media_service, "get_storage", lambda: CloudinaryLike())
        owner = make_user(db, "shopkeeper")
        shop = make_shop(db, owner=owner)
        with pytest.raises(StorageUnavailableError) as exc:
            media_service.create_upload_intent(
                db, owner,
                category_name="PRODUCT_IMAGE",
                filename="a.png",
                content_type="image/png",
                size_bytes=len(PNG_BYTES),
                shop_id=shop.id,
            )
        assert exc.value.error_code == "STORAGE_UNAVAILABLE"

# END_MARKER
