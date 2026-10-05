"""The input sanitizer must not lock a shopkeeper out of their own session.

The bug this pins was real and intermittent: a refresh token is
`secrets.token_urlsafe(48)` — one base64url segment, no dots — but the
token-skip rule only recognised a THREE-segment JWT. So every refresh token was
scanned as if it were user prose, and any that happened to contain `--`, `xp_` or
`sp_` was answered `400 INVALID_INPUT`. Roughly 1 refresh in 60 logged a shopkeeper
out at random, which is indistinguishable from a flaky app.

These tests fix the false positive and, just as importantly, prove the real
protection is still there.
"""

import re
import secrets

import pytest

from app.core.security_middleware import (
    InputSanitizationMiddleware,
    _is_token_field,
    _looks_like_jwt,
)


@pytest.fixture()
def sanitizer():
    instance = InputSanitizationMiddleware.__new__(InputSanitizationMiddleware)
    instance.sql_patterns = [
        re.compile(p, re.IGNORECASE) for p in InputSanitizationMiddleware.SQL_INJECTION_PATTERNS
    ]
    instance.xss_patterns = [
        re.compile(p, re.IGNORECASE) for p in InputSanitizationMiddleware.XSS_PATTERNS
    ]
    return instance


def _blocked(sanitizer, key, value) -> bool:
    if _is_token_field(key) or _looks_like_jwt(value):
        return False
    return sanitizer._contains_sql_injection(value) or sanitizer._contains_xss(value)


class TestRealRefreshTokensAreNeverRejected:
    def test_a_batch_of_real_tokens_is_never_rejected(self, sanitizer):
        """Sampled rather than hand-picked: the bug was intermittent, so a single
        hand-written token would have passed the old code by luck."""
        rejected = [
            token
            for token in (secrets.token_urlsafe(48) for _ in range(500))
            if _blocked(sanitizer, "refresh_token", token)
        ]
        assert not rejected, (
            f"{len(rejected)}/500 real refresh tokens were refused; a shopkeeper "
            f"carrying one is logged out. e.g. {rejected[:1]}"
        )

    def test_a_token_containing_a_comment_terminator_is_still_accepted(self):
        """The exact substring that used to trip the filter."""
        assert not _blocked(sanitizer, "refresh_token", "abc--def" + "x" * 40)

    def test_the_issued_token_shape_is_recognised(self):
        """`token_urlsafe(48)` has no dots -- the reason the old rule missed it."""
        token = secrets.token_urlsafe(48)
        assert "." not in token
        assert _looks_like_jwt(token) is True


class TestCredentialsAreExemptByFieldName:
    """Format-independent half of the fix: whatever a token looks like."""

    @pytest.mark.parametrize(
        "field",
        ["refresh_token", "access_token", "id_token", "token", "api_key", "authorization"],
    )
    def test_a_credential_field_is_never_scanned(self, sanitizer, field):
        assert _is_token_field(field) is True
        # Even a value that would otherwise match every pattern.
        hostile = "'; DROP TABLE shops; -- " + "a" * 32
        assert _blocked(sanitizer, field, hostile) is False

    def test_the_field_name_check_ignores_case_and_padding(self):
        assert _is_token_field("  Refresh_Token ") is True

    def test_a_prose_field_is_not_exempt_however_it_is_named(self, sanitizer):
        assert _is_token_field("description") is False
        assert _blocked(sanitizer, "description", "'; DROP TABLE shops; --") is True


class TestTheProtectionIsNotWeakened:
    """A false-positive fix that opens a hole is not a fix."""

    @pytest.mark.parametrize(
        "payload",
        [
            "'; DROP TABLE shops; --",
            "1 OR 1=1",
            "<script>alert(1)</script>",
            "Robert'); DROP TABLE students;--",
            "UNION ALL SELECT password FROM users",
            "<img src=x onerror=alert(1)>",
        ],
    )
    def test_a_real_attack_is_still_blocked(self, sanitizer, payload):
        assert _blocked(sanitizer, "message", payload) is True

    def test_a_nested_attack_inside_a_list_is_still_blocked(self, sanitizer):
        payload = {"items": ["harmless", "'; DROP TABLE shops; --"]}
        blocked = any(
            _blocked(sanitizer, key, value)
            for key, value in InputSanitizationMiddleware._iter_string_values(payload)
        )
        assert blocked is True

    def test_ordinary_prose_is_not_flagged(self, sanitizer):
        """The other half of the same concern: a merchant's words are not SQL."""
        for sentence in (
            "stock did not update after I changed the price",
            "delete product does nothing on my screen",
            "please create the offer before Friday",
            "the customer called about the update fee",
        ):
            assert _blocked(sanitizer, "description", sentence) is False


class TestTheIterYield:
    def test_values_are_yielded_with_their_field_name(self):
        payload = {"a": "x", "n": [{"b": "y"}], "c": 1, "d": None}
        got = dict(
            (k, v)
            for k, v in InputSanitizationMiddleware._iter_string_values(payload)
            if k is not None
        )
        assert got["a"] == "x"
        assert got["b"] == "y"

    def test_a_bare_string_still_yields(self):
        assert [v for _, v in InputSanitizationMiddleware._iter_string_values("hi")] == ["hi"]


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))