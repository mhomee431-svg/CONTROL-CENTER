"""Phase 2/3 - Media state-machine lifecycle tests (SQLite in-memory)."""
from __future__ import annotations

import os
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))
os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

import pytest  # noqa: E402
from sqlalchemy import create_engine  # noqa: E402
from sqlalchemy.orm import sessionmaker  # noqa: E402
from sqlalchemy.pool import StaticPool  # noqa: E402

from app.database.session import Base  # noqa: E402
from app.models.media import Media, MediaState  # noqa: E402
from app.services.media_lifecycle import (  # noqa: E402
    confirm_media,
    get_media_status,
    process_s3_event,
    record_upload_intent,
)

PNG_BYTES = b"\x89PNG\r\n\x1a\n" + b"\x00" * 16
EXE_BYTES = b"MZ\x90\x00\x03\x00" + b"\x00" * 16
PDF_BYTES = b"%PDF-1.7\n" + b"\x00" * 16
KEY = "products/12/2026/08/ab12cd34_photo.png"


class FakeProvider:
    """Dict-backed synchronous stand-in for the S3 provider."""

    def __init__(self, store=None):
        self.store = store or {}
        self.content_types = {}
        self.copied = []
        self.deleted = []

    def head_object(self, key):
        if key not in self.store:
            return None
        return {"content_type": self.content_types.get(key), "size": len(self.store[key])}

    def read_object_bytes(self, key, limit=8):
        return self.store[key][:limit]

    def copy_object(self, src, dst):
        self.store[dst] = self.store.get(src, b"")
        self.content_types[dst] = self.content_types.get(src)
        self.copied.append((src, dst))

    def delete_object(self, key):
        self.deleted.append(key)
        self.store.pop(key, None)


def _make_engine():
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    Base.metadata.create_all(engine, tables=[Media.__table__])
    return engine


@pytest.fixture
def db():
    engine = _make_engine()
    session = sessionmaker(bind=engine)()
    yield session
    session.close()
    engine.dispose()


def test_intent_creates_pending_row(db):
    media = record_upload_intent(db, key=KEY, category="PRODUCT_IMAGE", size_bytes=len(PNG_BYTES))
    assert media.state == MediaState.PENDING
    assert get_media_status(db, KEY).state == MediaState.PENDING


def test_valid_png_advances_to_ready(db):
    record_upload_intent(db, key=KEY, category="PRODUCT_IMAGE", size_bytes=len(PNG_BYTES))
    provider = FakeProvider()
    provider.store[KEY] = PNG_BYTES
    provider.content_types[KEY] = "image/png"
    result = process_s3_event(db, key=KEY, provider=provider, category="PRODUCT_IMAGE")
    assert result.state == MediaState.READY
    assert result.error_code is None
    assert result.processed_at is not None


def test_corrupt_exe_is_quarantined_and_failed(db):
    record_upload_intent(db, key=KEY, category="PRODUCT_IMAGE",
                         size_bytes=len(EXE_BYTES), content_type="image/png")
    provider = FakeProvider()
    provider.store[KEY] = EXE_BYTES
    provider.content_types[KEY] = "image/png"
    result = process_s3_event(db, key=KEY, provider=provider, category="PRODUCT_IMAGE")
    assert result.state == MediaState.FAILED
    assert result.error_code == "CONTENT_TYPE_MISMATCH"
    assert result.quarantine_key is not None
    assert KEY not in provider.store
    assert (KEY, result.quarantine_key) in provider.copied


def test_declared_vs_stored_size_mismatch_quarantined(db):
    record_upload_intent(db, key=KEY, category="PRODUCT_IMAGE", size_bytes=9999, content_type="image/png")
    provider = FakeProvider()
    provider.store[KEY] = PNG_BYTES
    provider.content_types[KEY] = "image/png"
    result = process_s3_event(db, key=KEY, provider=provider, category="PRODUCT_IMAGE")
    assert result.state == MediaState.FAILED
    assert result.error_code == "SIZE_MISMATCH"


def test_content_type_not_in_allowlist_rejected(db):
    record_upload_intent(db, key=KEY, category="PRODUCT_IMAGE",
                         size_bytes=len(PDF_BYTES), content_type="image/png")
    provider = FakeProvider()
    provider.store[KEY] = PDF_BYTES
    provider.content_types[KEY] = "image/png"
    result = process_s3_event(db, key=KEY, provider=provider, category="PRODUCT_IMAGE")
    assert result.state == MediaState.FAILED
    assert result.error_code == "CONTENT_TYPE_MISMATCH"


def test_object_missing_marked_failed(db):
    record_upload_intent(db, key=KEY, category="PRODUCT_IMAGE")
    provider = FakeProvider()
    result = process_s3_event(db, key=KEY, provider=provider, category="PRODUCT_IMAGE")
    assert result.state == MediaState.FAILED
    assert result.error_code == "OBJECT_MISSING"


def test_processing_is_idempotent_after_ready(db):
    record_upload_intent(db, key=KEY, category="PRODUCT_IMAGE", size_bytes=len(PNG_BYTES))
    provider = FakeProvider()
    provider.store[KEY] = PNG_BYTES
    provider.content_types[KEY] = "image/png"
    process_s3_event(db, key=KEY, provider=provider, category="PRODUCT_IMAGE")
    second = process_s3_event(db, key=KEY, provider=provider, category="PRODUCT_IMAGE")
    assert second.state == MediaState.READY
    assert provider.copied == []
    assert provider.deleted == []
    assert len(db.query(Media).filter(Media.key == KEY).all()) == 1


def test_confirm_upload_is_idempotent(db):
    record_upload_intent(db, key=KEY, category="PRODUCT_IMAGE", size_bytes=len(PNG_BYTES))
    provider = FakeProvider()
    provider.store[KEY] = PNG_BYTES
    provider.content_types[KEY] = "image/png"
    first = confirm_media(db, key=KEY, provider=provider)
    second = confirm_media(db, key=KEY, provider=provider)
    assert first.state == MediaState.UPLOADED
    assert second.state == MediaState.UPLOADED
    assert len(db.query(Media).filter(Media.key == KEY).all()) == 1


def test_reprocessing_failed_row_is_noop(db):
    record_upload_intent(db, key=KEY, category="PRODUCT_IMAGE", size_bytes=len(EXE_BYTES))
    provider = FakeProvider()
    provider.store[KEY] = EXE_BYTES
    provider.content_types[KEY] = "image/png"
    process_s3_event(db, key=KEY, provider=provider, category="PRODUCT_IMAGE")
    before = get_media_status(db, KEY)
    copied_before = list(provider.copied)
    process_s3_event(db, key=KEY, provider=provider, category="PRODUCT_IMAGE")
    after = get_media_status(db, KEY)
    assert before.state == MediaState.FAILED and after.state == MediaState.FAILED
    assert provider.copied == copied_before
