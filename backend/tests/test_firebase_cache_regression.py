"""REGRESSION — the two ways a valid Firebase token could still reach a 500.

Both bugs lived on the authentication path and neither could be caught by a
happy-path test, because each needed a specific *failure* to line up:

1. The token cache published a ``(None, exp_ts)`` placeholder BEFORE the claims
   were built. A token that verifies but carries no ``sub`` claim then raised
   while the placeholder was still cached, so every LATER request for that same
   token was served ``None`` — turning a clean 401 into ``TypeError``.

2. ``/auth/verify-phone`` unpacked the claims DICT into two names, which yields
   the dict's KEYS and raises ``ValueError``. That is not a
   ``FirebaseVerificationError``, so it escaped the handler as a 500.
"""

import pytest

from app.services import firebase_verification as fv


@pytest.fixture(autouse=True)
def _clean_cache():
    """Each test owns the cache; a leaked entry would hide the bug."""
    fv.clear_firebase_token_cache()
    yield
    fv.clear_firebase_token_cache()


def _install_fake_firebase(monkeypatch, decoded):
    """Stub Firebase Admin so the real code path runs with a chosen token."""

    class _FakeAuth:
        @staticmethod
        def verify_id_token(_token):
            return decoded

    class _FakeAdmin:
        auth = _FakeAuth()

    monkeypatch.setattr(fv, "_ensure_initialized", lambda: None)
    import firebase_admin

    monkeypatch.setattr(firebase_admin, "auth", _FakeAdmin().auth, raising=False)


def test_missing_sub_does_not_poison_the_cache(monkeypatch):
    """A verified token with no ``sub`` must not leave a ``None`` behind."""
    _install_fake_firebase(monkeypatch, {"exp": 9_999_999_999, "email": "a@b.c"})

    with pytest.raises(fv.FirebaseVerificationError):
        fv.verify_firebase_id_token_claims("header.payload.signature")

    # The failing path must have left NOTHING cached — a `(None, exp)` entry
    # would be served to the next caller as if it were a real hit.
    for payload, _exp in fv._verified_token_cache.values():
        assert payload is not None, "a failed verification left a None placeholder"


def test_poisoned_entry_is_treated_as_a_miss(monkeypatch):
    """Even if a poisoned entry exists, it must never be returned."""
    _install_fake_firebase(
        monkeypatch,
        {"sub": "uid-1", "exp": 9_999_999_999, "email": "a@b.c"},
    )

    fp = fv._token_fingerprint("header.payload.signature")
    # Simulate the state the old code could leave behind.
    fv._verified_token_cache[fp] = (None, 9_999_999_999)

    claims = fv.verify_firebase_id_token_claims("header.payload.signature")

    assert claims is not None, "a poisoned cache entry was served to the caller"
    assert claims["uid"] == "uid-1"


def test_verify_firebase_id_token_returns_real_values(monkeypatch):
    """The tuple helper must read FIELDS, never unpack the dict."""
    _install_fake_firebase(
        monkeypatch,
        {
            "sub": "uid-7",
            "phone_number": "+919000000000",
            "exp": 9_999_999_999,
        },
    )

    uid, phone = fv.verify_firebase_id_token("header.payload.signature")

    assert uid == "uid-7"
    assert phone == "+919000000000"


def test_verify_phone_route_does_not_unpack_the_claims_dict():
    """Guards the shape of the call inside the verify-phone handler.

    The bug was invisible to every other test because a dict unpacks into its
    KEYS without error when it happens to have two. This asserts the handler
    indexes the claims rather than unpacking them.
    """
    from pathlib import Path

    source = Path("app/api/routes/shopkeeper_auth.py").read_text(encoding="utf-8")
    handler = source.split("async def verify_phone", 1)[1]
    handler = handler.split("@router.", 1)[0]

    assert (
        "firebase_uid, phone = verify_firebase_id_token_claims(" not in handler
    ), "verify-phone must not unpack the claims dict into two names"
    assert 'verified["uid"]' in handler, "verify-phone must read the uid field"
    assert 'verified["phone"]' in handler, "verify-phone must read the phone field"


def test_verify_otp_route_does_not_compare_a_dict_to_a_phone_column():
    """Same class of bug in `/verify-otp`, which fed the claims DICT into a
    `User.phone_number == phone` lookup — a string column that could never
    match a dict, so the endpoint silently reported ACCOUNT_NOT_FOUND for every
    real caller."""
    from pathlib import Path

    source = Path("app/api/routes/shopkeeper_auth.py").read_text(encoding="utf-8")
    handler = source.split("async def verify_otp_login", 1)[1]
    handler = handler.split("@router.", 1)[0]

    assert (
        "phone = verify_firebase_id_token_claims(" not in handler
    ), "verify-otp must not assign the whole claims dict to `phone`"
    assert 'phone = verified["phone"]' in handler, (
        "verify-otp must read the phone field before querying by it"
    )


def test_routes_read_claims_fields_never_unpack_them():
    """A blanket guard across EVERY module that consumes the claims dict.

    All three of these bugs had the same shape — the real function returns a
    dict, the call site assumed something else — and two of them were hidden
    because the tests mocked the function to return whatever the call site
    happened to want. This pins the contract at every call site at once, and
    scans all of `app/` rather than one router, so a NEW route cannot repeat it.

    The correct shapes are either indexing (`verified["phone"]`) or delegating to
    the tuple helper (`verify_firebase_id_token`), which is why the rule is
    "the bound name must be indexed", not "never assign".
    """
    from pathlib import Path

    offenders = []
    saw_a_real_use = False

    for path in sorted(Path("app").rglob("*.py")):
        source = path.read_text(encoding="utf-8")
        if "verify_firebase_id_token_claims(" not in source:
            continue

        for lineno, line in enumerate(source.splitlines(), start=1):
            stripped = line.strip()
            if stripped.startswith("#"):
                continue

            # `a, b = verify_firebase_id_token_claims(...)` unpacks the dict
            # into its KEYS. Catch that shape explicitly.
            if "verify_firebase_id_token_claims(" in stripped:
                lhs, _, _rhs = stripped.partition("=")
                if "," in lhs and "verify_firebase_id_token_claims(" in stripped:
                    offenders.append(
                        f"{path}:{lineno}: `{stripped}` unpacks the claims DICT "
                        "into names, which yields its KEYS"
                    )
                    continue

                # `name = verify_firebase_id_token_claims(...)` is only a bug
                # when `name` is never indexed anywhere in the module.
                name = lhs.strip()
                if name and name.isidentifier():
                    if f'{name}["' in source or f"{name}['" in source:
                        saw_a_real_use = True
                    elif "def " not in lhs:
                        offenders.append(
                            f"{path}:{lineno}: `{stripped}` holds the claims "
                            "DICT but is never indexed — a caller using it as a "
                            "scalar gets a dict where a str/int is meant"
                        )

    assert saw_a_real_use, (
        "sanity: the claims helper is really used somewhere, so the index "
        "detector above is actually matching"
    )
    assert not offenders, "claims-dict misuse:\n" + "\n".join(offenders)


def test_cache_still_honours_its_size_cap(monkeypatch):
    """The size bound was moved; it must still actually bound."""
    _install_fake_firebase(
        monkeypatch,
        {"sub": "uid-9", "exp": 9_999_999_999},
    )

    monkeypatch.setattr(fv, "_MAX_CACHE_SIZE", 4)
    for i in range(20):
        fv.verify_firebase_id_token_claims(f"header.payload.sig{i}")

    assert len(fv._verified_token_cache) <= 4, (
        "the verified-token cache grew past its configured bound"
    )
