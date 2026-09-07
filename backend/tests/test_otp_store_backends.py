"""Tests for the OTP storage abstraction (in-memory + Redis backends).

The Redis backend is exercised two ways:
  1. Unit tests through a fake client (no live Redis required).
  2. Integration tests against a live Redis on localhost:6379/15 —
     automatically skipped when Redis is unreachable (e.g. no Docker).
"""

import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

import pytest  # noqa: E402

from app.core.config import settings  # noqa: E402
from app.services import otp_service  # noqa: E402
from app.services import otp_store as otp_store_module  # noqa: E402
from app.services.otp_store import (  # noqa: E402
    InMemoryOTPStore,
    RedisOTPStore,
    create_otp_store,
    reset_otp_store,
)


class FakeRedis:
    """Minimal redis client stand-in (get / setex / delete)."""

    def __init__(self):
        self.data: dict[str, str] = {}
        self.ttls: dict[str, int] = {}

    def get(self, key):
        return self.data.get(key)

    def setex(self, key, ttl, value):
        self.data[key] = value
        self.ttls[key] = ttl

    def delete(self, key):
        return self.data.pop(key, None) is not None

    def scan_iter(self, match=None):
        prefix = (match or "*").rstrip("*")
        for key in list(self.data):
            if key.startswith(prefix):
                yield key


def _record(**overrides):
    now = datetime.now(timezone.utc)
    base = {
        "otp_hash": "a" * 64,
        "salt": "b" * 32,
        "expires_at": now + timedelta(minutes=5),
        "attempts": 0,
        "resend_count": 1,
        "last_resend_at": now,
        "created_at": now,
    }
    base.update(overrides)
    return base


@pytest.fixture(autouse=True)
def _isolate_singleton():
    reset_otp_store()
    yield
    reset_otp_store()


# ── Serialization ────────────────────────────────────────────────────────────
class TestSerialization:
    def test_datetime_round_trip(self):
        from app.services.otp_store import _deserialize, _serialize

        record = _record()
        restored = _deserialize(_serialize(record))
        for key in ("expires_at", "last_resend_at", "created_at"):
            assert restored[key] == record[key]
        assert restored["otp_hash"] == record["otp_hash"]
        assert restored["attempts"] == 0

    def test_service_logic_works_on_restored_record(self):
        """verify_otp compares datetimes — a Redis-restored record must behave."""
        from app.services.otp_store import _deserialize, _serialize

        restored = _deserialize(_serialize(_record()))
        assert datetime.now(timezone.utc) <= restored["expires_at"]


# ── In-memory backend ────────────────────────────────────────────────────────
class TestInMemoryStore:
    def test_set_get_pop(self):
        store = InMemoryOTPStore()
        store.set("+919810000001", _record(), ttl_seconds=300)
        assert store.get("+919810000001") is not None
        store.pop("+919810000001")
        assert store.get("+919810000001") is None

    def test_pop_missing_key_is_noop(self):
        store = InMemoryOTPStore()
        store.pop("+919810000002")  # must not raise


# ── Redis backend (fake client) ──────────────────────────────────────────────
class TestRedisStoreWithFakeClient:
    def test_set_uses_ttl(self):
        fake = FakeRedis()
        store = RedisOTPStore("redis://fake", client=fake)
        store.set("+919810000003", _record(), ttl_seconds=360)
        assert fake.ttls["otp:+919810000003"] == 360

    def test_round_trip_preserves_data(self):
        fake = FakeRedis()
        store = RedisOTPStore("redis://fake", client=fake)
        record = _record(resend_count=3, attempts=2)
        store.set("+919810000004", record, ttl_seconds=300)
        got = store.get("+919810000004")
        assert got["resend_count"] == 3
        assert got["attempts"] == 2
        assert got["expires_at"] == record["expires_at"]

    def test_pop_removes_key(self):
        fake = FakeRedis()
        store = RedisOTPStore("redis://fake", client=fake)
        store.set("+919810000005", _record(), ttl_seconds=300)
        store.pop("+919810000005")
        assert store.get("+919810000005") is None

    def test_get_missing_returns_none(self):
        store = RedisOTPStore("redis://fake", client=FakeRedis())
        assert store.get("+919810000006") is None


# ── Factory ──────────────────────────────────────────────────────────────────
class TestFactory:
    def test_memory_uri(self):
        assert isinstance(create_otp_store("memory://"), InMemoryOTPStore)

    def test_unknown_scheme_rejected(self):
        with pytest.raises(ValueError, match="Unsupported OTP_STORAGE_URI"):
            create_otp_store("memcached://localhost:11211")

    def test_get_otp_store_caches_by_uri(self):
        settings.OTP_STORAGE_URI = "memory://"
        first = otp_store_module.get_otp_store(settings.OTP_STORAGE_URI)
        second = otp_store_module.get_otp_store(settings.OTP_STORAGE_URI)
        assert first is second

    def test_uri_change_rebuilds_store(self):
        settings.OTP_STORAGE_URI = "memory://"
        first = otp_store_module.get_otp_store(settings.OTP_STORAGE_URI)
        otp_store_module._active_store = RedisOTPStore("redis://fake", client=FakeRedis())
        otp_store_module._active_uri = "redis://fake"
        other = otp_store_module.get_otp_store("redis://fake")
        assert other is otp_store_module._active_store
        assert other is not first


# ── Full service flows through the Redis backend ─────────────────────────────
class TestOTPServiceWithRedisBackend:
    @pytest.fixture()
    def redis_backed_service(self, monkeypatch):
        fake = FakeRedis()
        store = RedisOTPStore("redis://fake", client=fake)
        otp_store_module._active_store = store
        otp_store_module._active_uri = "redis://fake"
        monkeypatch.setattr(settings, "OTP_STORAGE_URI", "redis://fake")
        monkeypatch.setattr(settings, "OTP_RESEND_COOLDOWN_SECONDS", 0)
        return store

    def test_generate_and_verify(self, redis_backed_service):
        phone = "+919810000007"
        otp_service.generate_otp(phone)
        assert otp_service.verify_otp(phone, settings.OTP_DEV_VALUE) is True

    def test_verify_unknown_phone(self, redis_backed_service):
        assert otp_service.verify_otp("+919810000008", "000000") is False

    def test_single_use(self, redis_backed_service):
        phone = "+919810000009"
        otp_service.generate_otp(phone)
        assert otp_service.verify_otp(phone, settings.OTP_DEV_VALUE) is True
        assert otp_service.verify_otp(phone, settings.OTP_DEV_VALUE) is False

    def test_max_attempts_invalidate(self, redis_backed_service, monkeypatch):
        monkeypatch.setattr(settings, "OTP_MAX_ATTEMPTS", 2)
        phone = "+919810000010"
        otp_service.generate_otp(phone)
        assert otp_service.verify_otp(phone, "000000") is False
        assert otp_service.verify_otp(phone, "000000") is False
        assert otp_service.verify_otp(phone, settings.OTP_DEV_VALUE) is False

    def test_resend_limit_persists_in_backend(self, redis_backed_service, monkeypatch):
        monkeypatch.setattr(settings, "OTP_MAX_RESENDS", 2)
        phone = "+919810000011"
        otp_service.generate_otp(phone)
        otp_service.resend_otp(phone)
        with pytest.raises(otp_service.OTPLimitExceeded):
            otp_service.resend_otp(phone)

    def test_expiry_pops_record(self, redis_backed_service):
        phone = "+919810000012"
        otp_service.generate_otp(phone)
        record = redis_backed_service.get(phone)
        record["expires_at"] = datetime.now(timezone.utc) - timedelta(seconds=1)
        redis_backed_service.set(phone, record, ttl_seconds=60)
        assert otp_service.verify_otp(phone, settings.OTP_DEV_VALUE) is False
        assert redis_backed_service.get(phone) is None

    def test_clear_otp(self, redis_backed_service):
        phone = "+919810000013"
        otp_service.generate_otp(phone)
        otp_service.clear_otp(phone)
        assert otp_service.verify_otp(phone, settings.OTP_DEV_VALUE) is False


# ── Live Redis integration (skipped without Docker/Redis) ────────────────────
def _live_redis_available() -> bool:
    try:
        import redis as redis_sync

        client = redis_sync.Redis.from_url(
            "redis://127.0.0.1:6379/15",
            socket_connect_timeout=0.5,
            socket_timeout=0.5,
        )
        return bool(client.ping())
    except Exception:  # noqa: BLE001 — unreachable Redis just means skip
        return False


@pytest.mark.skipif(not _live_redis_available(), reason="live Redis not reachable on :6379")
class TestLiveRedis:
    TEST_DB_URI = "redis://127.0.0.1:6379/15"

    def test_generate_and_verify_through_real_redis(self):
        reset_otp_store()
        settings.OTP_STORAGE_URI = self.TEST_DB_URI
        try:
            store = create_otp_store(self.TEST_DB_URI)
            phone = "+919810099999"
            otp_store_module._active_store = store
            otp_store_module._active_uri = self.TEST_DB_URI
            otp_service.generate_otp(phone)
            # The record really is in Redis:
            assert store.get(phone) is not None
            assert otp_service.verify_otp(phone, settings.OTP_DEV_VALUE) is True
            # Single-use → record gone from Redis:
            assert store.get(phone) is None
        finally:
            reset_otp_store()

    def test_ttl_is_set(self):
        reset_otp_store()
        try:
            store = create_otp_store(self.TEST_DB_URI)
            phone = "+919810088888"
            store.set(phone, _record(), ttl_seconds=120)
            import redis as redis_sync

            client = redis_sync.Redis.from_url(self.TEST_DB_URI, decode_responses=True)
            ttl = client.ttl(f"otp:{phone}")
            assert 0 < ttl <= 120
            client.delete(f"otp:{phone}")
        finally:
            reset_otp_store()

