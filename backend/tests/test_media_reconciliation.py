"""Phase 3 - Reconciliation cron tests (SQLite in-memory).

Verifies reconcile_stale_media finalizes Media rows stuck in PROCESSING past
the staleness window, advancing a valid object to READY.
"""
from __future__ import annotations

import os
import sys
from datetime import datetime, timedelta, timezone
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
from app.services.media_reconciliation import reconcile_stale_media  # noqa: E402
from app.services.media_lifecycle import process_s3_event  # noqa: E402

PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 16
KEY = "products/12/2026/08/ab12cd34_photo.png"


class FakeProvider:
    def __init__(self):
        self.store = {}
        self.content_types = {}

    def head_object(self, key):
        if key not in self.store:
            return None
        return {"content_type": self.content_types.get(key), "size": len(self.store[key])}

    def read_object_bytes(self, key, limit=8):
        return self.store[key][:limit]

    def copy_object(self, src, dst):
        self.store[dst] = self.store.get(src, b"")
        self.content_types[dst] = self.content_types.get(src)

    def delete_object(self, key):
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


def test_reconcile_advances_ready_object(db):
    media = Media(
        key=KEY, category="PRODUCT_IMAGE", state=MediaState.PROCESSING,
        content_type="image/png", size_bytes=len(PNG),
        processed_at=datetime.now(timezone.utc) - timedelta(minutes=20),
    )
    db.add(media)
    db.commit()
    db.refresh(media)
    media.updated_at = datetime.now(timezone.utc) - timedelta(minutes=20)
    db.commit()

    provider = FakeProvider()
    provider.store[KEY] = PNG
    provider.content_types[KEY] = "image/png"

    finalized = reconcile_stale_media(db, provider, stale_minutes=10)
    assert finalized == 1
    db.refresh(media)
    assert media.state == MediaState.READY


def test_reconcile_leaves_recent_processing_untouched(db):
    media = Media(
        key=KEY, category="PRODUCT_IMAGE", state=MediaState.PROCESSING,
        content_type="image/png", size_bytes=len(PNG),
    )
    db.add(media)
    db.commit()
    db.refresh(media)

    provider = FakeProvider()
    provider.store[KEY] = PNG
    provider.content_types[KEY] = "image/png"

    finalized = reconcile_stale_media(db, provider, stale_minutes=10)
    assert finalized == 0
    db.refresh(media)
    assert media.state == MediaState.PROCESSING
