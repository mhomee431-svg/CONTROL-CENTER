"""Tests for the Fast2SMS single-use OTP flow.

Covers the DB-backed OTP service (:mod:`app.services.fast2sms_otp_service`),
the delivery helper (:mod:`app.services.fast2sms`), and the customer auth
routes built on top of them. A lightweight in-memory ``FakeSession`` stands in
for SQLAlchemy so the services can be exercised without a live database.
"""
import asyncio
import datetime
import operator as op
from unittest.mock import MagicMock, patch

import pytest

# ── In-memory SQLAlchemy stand-in ─────────────────────────────────────────────
# The service only needs query/filter/sort/first/count, add/flush, and an
# ``execute(update(...))`` supporting the single-use flip. We interpret the
# SQLAlchemy expression objects generically instead of reaching into internals.


def _right_value(expr):
    r = expr.right
    name = type(r).__name__
    # SQLAlchemy renders ``col.is_(False)`` with a False_/True_ literal element.
    if name == "False_":
        return False
    if name == "True_":
        return True
    return getattr(r, "value", r)


def _eval(record, expr):
    """Evaluate a SQLAlchemy BinaryExpression against an ORM-like record."""
    from sqlalchemy.sql.elements import BinaryExpression

    if not isinstance(expr, BinaryExpression):
        raise TypeError(f"Unhandled expression: {type(expr).__name__}")
    left = expr.left
    col_name = getattr(left, "key", None)
    value = getattr(record, col_name) if col_name else None
    fn = expr.operator
    fn_name = getattr(fn, "__name__", str(fn))
    if fn_name == "eq":
        return value == _right_value(expr)
    if fn_name == "gt":
        return value > _right_value(expr)
    if fn_name == "is_":
        return value is _right_value(expr)
    raise TypeError(f"Unhandled operator: {fn_name}")


def _where(record, whereclause):
    from sqlalchemy.sql.elements import BooleanClauseList

    if whereclause is None:
        return True
    if isinstance(whereclause, BooleanClauseList):
        return all(_eval(record, c) for c in whereclause.clauses)
    return _eval(record, whereclause)


class _FakeQuery:
    def __init__(self, rows):
        self._rows = list(rows)
        self._preds = []

    def filter(self, *exprs):
        q = _FakeQuery(self._rows)
        q._preds = list(self._preds) + list(exprs)
        return q

    def order_by(self, *_):
        self._rows = sorted(self._rows, key=lambda r: getattr(r, "id") or 0, reverse=True)
        return self

    def _matched(self):
        return [r for r in self._rows if all(_where(r, p) for p in self._preds)]

    def first(self):
        rows = self._matched()
        return rows[0] if rows else None

    def count(self):
        return len(self._matched())


class FakeSession:
    """Minimal stand-in for ``sqlalchemy.orm.Session`` as used by the service."""

    def __init__(self):
        self.rows = []
        self._id = 0

    def query(self, *_):
        return _FakeQuery(self.rows)

    def add(self, obj):
        self._id += 1
        obj.id = getattr(obj, "id", None) or self._id
        if getattr(obj, "created_at", None) is None:
            obj.created_at = datetime.datetime.now(datetime.timezone.utc)
        self.rows.append(obj)

    def flush(self):
        pass

    def rollback(self):
        pass

    def execute(self, stmt):
        whereclause = getattr(stmt, "whereclause", None)
        values = dict(getattr(stmt, "_values", {}))
        n = 0
        for record in self.rows:
            if _where(record, whereclause):
                for col, val in values.items():
                    col_name = getattr(col, "key", col)
                    setattr(record, col_name, val)
                n += 1
        return MagicMock(rowcount=n)


def run_async(coro):
    return asyncio.run(coro)


@pytest.fixture(autouse=True)
def _reset_settings():
    from app.core.config import settings

    prev = (
        settings.OTP_COOLDOWN_SECONDS,
        settings.OTP_MAX_RESENDS,
        settings.OTP_DEV_MODE,
        settings.OTP_MODE,
    )
    settings.OTP_COOLDOWN_SECONDS = 0
    settings.OTP_MAX_RESENDS = 5
    settings.OTP_DEV_MODE = True
    settings.OTP_MODE = "mock"
    yield
    (
        settings.OTP_COOLDOWN_SECONDS,
        settings.OTP_MAX_RESENDS,
        settings.OTP_DEV_MODE,
        settings.OTP_MODE,
    ) = prev
# ── Service: generate & deliver ───────────────────────────────────────────────
class TestGenerateOtp:
    def test_generates_and_persists(self):
        from app.services import fast2sms_otp_service as svc

        db = FakeSession()
        result = svc.generate_otp(db, "+919999999999")
        assert result["expires_in"] == 300
        assert result["dev_otp"] == "123456"  # OTP_DEV_MODE
        assert len(db.rows) == 1
        row = db.rows[0]
        assert row.phone_number == "+919999999999"
        assert row.is_verified is False
        # Never store a raw code — only a salted digest.
        assert row.otp_code != result["dev_otp"]
        assert ":" in row.otp_code

    def test_delivers_via_fast2sms(self):
        from app.services import fast2sms_otp_service as svc

        db = FakeSession()
        with patch("app.services.fast2sms.send_otp_sms") as mock_send:
            result = svc.generate_otp(db, "919999999998")
        mock_send.assert_called_once()
        phone, code = mock_send.call_args.args
        assert phone == "+919999999998"
        assert code == result["dev_otp"]

    def test_cooldown_blocks_resend(self):
        from app.core.config import settings
        from app.services import fast2sms_otp_service as svc
        from app.services.otp_service import OTPCooldownError

        settings.OTP_COOLDOWN_SECONDS = 60
        db = FakeSession()
        with patch("app.services.fast2sms.send_otp_sms"):
            svc.generate_otp(db, "+919999999997")
        with patch("app.services.fast2sms.send_otp_sms"):
            with pytest.raises(OTPCooldownError):
                svc.generate_otp(db, "+919999999997")

    def test_resend_limit(self):
        from app.core.config import settings
        from app.services import fast2sms_otp_service as svc
        from app.services.otp_service import OTPLimitExceeded

        settings.OTP_COOLDOWN_SECONDS = 0
        settings.OTP_MAX_RESENDS = 1
        db = FakeSession()
        with patch("app.services.fast2sms.send_otp_sms"):
            svc.generate_otp(db, "+919999999996")
        with patch("app.services.fast2sms.send_otp_sms"):
            with pytest.raises(OTPLimitExceeded):
                svc.generate_otp(db, "+919999999996")
# ── Service: verify & single-use ─────────────────────────────────────────────
class TestVerifyOtp:
    def _issued(self, phone="+919999999995", expiry=None):
        from app.services import fast2sms_otp_service as svc

        db = FakeSession()
        with patch("app.services.fast2sms.send_otp_sms"):
            svc.generate_otp(db, phone)
        row = db.rows[0]
        if expiry is not None:
            row.expires_at = expiry
        return db, row, svc

    def test_valid_and_single_use(self):
        from app.services.fast2sms_otp_service import (
            VERIFY_ALREADY_USED,
            VERIFY_VALID,
        )

        db, row, svc = self._issued()
        assert svc.verify_otp(db, "+919999999995", "123456") == VERIFY_VALID
        assert row.is_verified is True  # consumed immediately
        # Second attempt with the same (now-used) code is rejected.
        assert svc.verify_otp(db, "+919999999995", "123456") == VERIFY_ALREADY_USED

    def test_invalid_code(self):
        from app.services.fast2sms_otp_service import VERIFY_INVALID

        db, row, svc = self._issued()
        assert svc.verify_otp(db, "+919999999995", "000000") == VERIFY_INVALID
        assert row.is_verified is False  # wrong code does not consume it

    def test_unknown_phone(self):
        from app.services.fast2sms_otp_service import VERIFY_INVALID

        db, row, svc = self._issued()
        assert svc.verify_otp(db, "+919999999999", "123456") == VERIFY_INVALID

    def test_expired(self):
        from app.services.fast2sms_otp_service import VERIFY_EXPIRED

        db, row, svc = self._issued(
            expiry=datetime.datetime.now(datetime.timezone.utc)
            - datetime.timedelta(seconds=1)
        )
        assert svc.verify_otp(db, "+919999999995", "123456") == VERIFY_EXPIRED
        assert row.is_verified is False

    def test_clear_consumes(self):
        from app.services.fast2sms_otp_service import (
            VERIFY_ALREADY_USED,
            VERIFY_VALID,
        )

        db, row, svc = self._issued()
        svc.clear_otp(db, "+919999999995")
        assert row.is_verified is True
        assert svc.verify_otp(db, "+919999999995", "123456") == VERIFY_ALREADY_USED
# ── Delivery helper ───────────────────────────────────────────────────────────
class TestFast2SmsDelivery:
    def test_mock_prints_and_never_sends(self):
        from app.core.config import settings
        from app.services import fast2sms

        settings.OTP_MODE = "mock"
        with patch("httpx.post") as mock_post, patch("builtins.print") as mock_print:
            fast2sms.send_otp_sms("+919999999994", "123456")
        mock_post.assert_not_called()
        mock_print.assert_called_once()
        assert "123456" in str(mock_print.call_args)

    def test_live_posts_expected_payload(self):
        from app.core.config import settings
        from app.services import fast2sms

        settings.OTP_MODE = "live"
        settings.FAST2SMS_API_KEY = "test-key"
        resp = MagicMock()
        resp.status_code = 200
        resp.json.return_value = {"return": True}
        with patch("httpx.post", return_value=resp) as mock_post:
            fast2sms.send_otp_sms("+91 99999 99993", "654321")
        req = mock_post.call_args
        assert req.args[0] == "https://www.fast2sms.com/dev/bulkV2"
        payload = req.kwargs["json"]
        assert payload == {
            "route": "otp",
            "variables_values": "654321",
            "numbers": "919999999993",
        }
        assert req.kwargs["headers"]["authorization"] == "test-key"

    def test_live_missing_key_raises(self):
        from app.core.config import settings
        from app.services import fast2sms

        settings.OTP_MODE = "live"
        settings.FAST2SMS_API_KEY = ""
        with pytest.raises(fast2sms.Fast2SMSDeliveryError):
            fast2sms.send_otp_sms("+919999999992", "123456")

    def test_live_http_error_raises(self):
        from app.core.config import settings
        from app.services import fast2sms

        settings.OTP_MODE = "live"
        settings.FAST2SMS_API_KEY = "test-key"
        resp = MagicMock()
        resp.status_code = 400
        resp.text = "boom"
        with patch("httpx.post", return_value=resp):
            with pytest.raises(fast2sms.Fast2SMSDeliveryError):
                fast2sms.send_otp_sms("+919999999991", "123456")


# ── Routes ────────────────────────────────────────────────────────────────────
class TestAuthRoutes:
    def test_send_otp_route_success(self):
        from app.api.routes.auth import send_otp
        from app.schemas.auth import SendOTPRequest

        with patch("app.api.routes.auth.generate_otp") as mock_gen:
            mock_gen.return_value = {"expires_in": 300, "dev_otp": "123456"}
            response = run_async(
                send_otp(
                    SendOTPRequest(phone_number="+919999999990"),
                    MagicMock(),
                    MagicMock(),
                )
            )
        assert response.status_code == 200
        assert b"123456" in response.body

    def test_send_otp_route_delivery_failure(self):
        from app.api.routes.auth import send_otp
        from app.schemas.auth import SendOTPRequest
        from app.services.fast2sms import Fast2SMSDeliveryError

        with patch("app.api.routes.auth.generate_otp", side_effect=Fast2SMSDeliveryError("x")):
            response = run_async(
                send_otp(
                    SendOTPRequest(phone_number="+919999999990"),
                    MagicMock(),
                    MagicMock(),
                )
            )
        assert response.status_code == 502
        assert b"SMS_DELIVERY_FAILED" in response.body

    def test_verify_otp_route_expired(self):
        from app.api.routes.auth import verify_otp_endpoint
        from app.schemas.auth import VerifyOTPRequest
        from app.services.fast2sms_otp_service import VERIFY_EXPIRED

        with patch("app.api.routes.auth.verify_otp", return_value=VERIFY_EXPIRED):
            response = run_async(
                verify_otp_endpoint(
                    VerifyOTPRequest(phone_number="+919999999990", otp="123456"),
                    MagicMock(),
                    MagicMock(),
                )
            )
        assert response.status_code == 400
        assert b"OTP_EXPIRED" in response.body

    def test_verify_otp_route_already_used(self):
        from app.api.routes.auth import verify_otp_endpoint
        from app.schemas.auth import VerifyOTPRequest
        from app.services.fast2sms_otp_service import VERIFY_ALREADY_USED

        with patch("app.api.routes.auth.verify_otp", return_value=VERIFY_ALREADY_USED):
            response = run_async(
                verify_otp_endpoint(
                    VerifyOTPRequest(phone_number="+919999999990", otp="123456"),
                    MagicMock(),
                    MagicMock(),
                )
            )
        assert response.status_code == 400
        assert b"OTP_ALREADY_USED" in response.body


# ── Config ────────────────────────────────────────────────────────────────────
class TestConfig:
    def test_otp_mode_validator(self):
        from app.core.config import Settings

        with pytest.raises(Exception):
            Settings(OTP_MODE="banana", _env_file=None)
        assert Settings(OTP_MODE="LIVE", _env_file=None).OTP_MODE == "live"

    def test_otp_model_metadata_registered(self):
        from app.database.session import Base
        from app.models import otp as otp_model  # noqa: F401

        assert "otps" in Base.metadata.tables