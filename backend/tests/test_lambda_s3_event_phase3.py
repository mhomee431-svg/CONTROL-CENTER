"""Phase 3 - Lambda S3-event handler tests (SQLite in-memory, no AWS)."""
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

import lambda_function  # backend/lambda_function.py at repo root  # noqa: E402

PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 16
EXE = b"MZ\x90\x00\x03\x00" + b"\x00" * 16
KEY = "products/12/2026/08/ab12cd34_photo.png"
EB_BAD = "products/12/2026/08/deadbeef_bad.png"


class FakeProvider:
    def __init__(self):
        self.store = {}
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
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    Base.metadata.create_all(engine, tables=[Media.__table__])
    return engine


@pytest.fixture
def engine():
    eng = _make_engine()
    yield eng
    eng.dispose()


@pytest.fixture
def db_factory(engine):
    return sessionmaker(bind=engine)


def _records_event(key, size):
    return {"Records": [{"s3": {"bucket": {"name": "b"},
                                 "object": {"key": key, "size": size}}}]}


def _eventbridge_event(key, size):
    return {"version": "0", "id": "x", "detail-type": "ObjectCreated:Put",
            "source": "aws.s3",
            "detail": {"bucket": {"name": "b"}, "object": {"key": key, "size": size}}}


def test_lambda_processes_valid_object_to_ready(engine, db_factory):
    provider = FakeProvider()
    provider.store[KEY] = PNG
    provider.content_types[KEY] = "image/png"
    result = lambda_function.lambda_handler(
        _records_event(KEY, len(PNG)), provider=provider, db_factory=db_factory
    )
    assert result["processed"] == 1 and result["errors"] == []
    session = db_factory()
    media = session.query(Media).filter(Media.key == KEY).first()
    assert media.state == MediaState.READY
    session.close()


def test_lambda_quarantines_corrupt_object(engine, db_factory):
    provider = FakeProvider()
    provider.store[EB_BAD] = EXE
    provider.content_types[EB_BAD] = "image/png"
    result = lambda_function.lambda_handler(
        _records_event(EB_BAD, len(EXE)), provider=provider, db_factory=db_factory
    )
    assert result["processed"] == 1
    session = db_factory()
    media = session.query(Media).filter(Media.key == EB_BAD).first()
    assert media.state == MediaState.FAILED
    assert media.error_code == "CONTENT_TYPE_MISMATCH"
    assert media.quarantine_key is not None
    session.close()


def test_lambda_handles_eventbridge_payload_shape(engine, db_factory):
    provider = FakeProvider()
    provider.store[KEY] = PNG
    provider.content_types[KEY] = "image/png"
    result = lambda_function.lambda_handler(
        _eventbridge_event(KEY, len(PNG)), provider=provider, db_factory=db_factory
    )
    assert result["processed"] == 1
    session = db_factory()
    assert session.query(Media).filter(Media.key == KEY).first().state == MediaState.READY
    session.close()


def test_lambda_is_idempotent_on_redelivery(engine, db_factory):
    provider = FakeProvider()
    provider.store[KEY] = PNG
    provider.content_types[KEY] = "image/png"
    handler = lambda_function.lambda_handler
    handler(_records_event(KEY, len(PNG)), provider=provider, db_factory=db_factory)
    result = handler(_records_event(KEY, len(PNG)), provider=provider, db_factory=db_factory)
    assert result["processed"] == 1
    assert provider.copied == []


def test_lambda_reconcile_cron_finalizes_stuck_processing(engine, db_factory):
    from datetime import datetime, timedelta, timezone
    session = db_factory()
    media = Media(
        key=KEY, category="PRODUCT_IMAGE", state=MediaState.PROCESSING,
        content_type="image/png", size_bytes=len(PNG),
        processed_at=datetime.now(timezone.utc) - timedelta(minutes=20),
    )
    session.add(media)
    session.commit()
    session.refresh(media)
    media.updated_at = datetime.now(timezone.utc) - timedelta(minutes=20)
    session.commit()
    session.close()
    provider = FakeProvider()
    provider.store[KEY] = PNG
    provider.content_types[KEY] = "image/png"
    result = lambda_function.lambda_handler(
        {"cron": "reconcile"}, provider=provider, db_factory=db_factory
    )
    assert result["reconciled"] == 1
    check = db_factory()
    assert check.query(Media).filter(Media.key == KEY).first().state == MediaState.READY
    check.close()
