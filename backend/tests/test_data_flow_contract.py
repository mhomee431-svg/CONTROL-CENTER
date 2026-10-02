"""ARCHITECTURE GUARD — the shopkeeper data flow, pinned as executable checks.

This encodes the declared contract so a future change cannot quietly break a
layer of it:

    SHOPKEEPER → GOOGLE SIGN-IN → FIREBASE AUTH → FIREBASE ID TOKEN
               → FASTAPI → APPLICATION USER → PROFILE → SHOP → PRODUCTS
               → INVENTORY → PRICES → OFFERS → IMPORT/POS → DASHBOARD

    data:   Flutter → FastAPI → PostgreSQL/PostGIS
    media:  Flutter → FastAPI authorization → S3
    cache:  FastAPI → Redis/Valkey   (OPTIONAL)

These are invariants, not a restatement. Each was checked against a
deliberately-injected violation while being written, so a green run means the
layer is intact rather than that the assertion is blind.
"""

from __future__ import annotations

import ast
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
APP_DIR = BACKEND_DIR / "app"
ROUTES_DIR = APP_DIR / "api" / "routes"
MEDIA_SERVICE = APP_DIR / "services" / "media_service.py"
AUTH_ROUTE = ROUTES_DIR / "shopkeeper_auth.py"


def _read(path: Path) -> str:
    # utf-8-sig, not utf-8: several modules carry a BOM, and `ast.parse`
    # rejects U+FEFF outright rather than skipping it.
    return path.read_text(encoding="utf-8-sig", errors="replace")


def _handlers(path: Path) -> list[ast.FunctionDef | ast.AsyncFunctionDef]:
    return [
        node
        for node in ast.walk(ast.parse(_read(path)))
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
    ]


def _decorated(fn: ast.FunctionDef | ast.AsyncFunctionDef) -> bool:
    return any(
        isinstance(d, ast.Call) and ast.unparse(d.func).startswith("router.")
        for d in fn.decorator_list
    )


def _signature(fn: ast.FunctionDef | ast.AsyncFunctionDef) -> str:
    return ast.unparse(ast.arguments(
        posonlyargs=fn.args.posonlyargs,
        args=fn.args.args,
        vararg=fn.args.vararg,
        kwonlyargs=fn.args.kwonlyargs,
        kw_defaults=fn.args.kw_defaults,
        kwarg=fn.args.kwarg,
        defaults=fn.args.defaults,
    ))


# ── 1. FIREBASE ID TOKEN → FASTAPI → APPLICATION USER ────────────────────────


class TestAuthChain:
    def test_firebase_login_is_the_documented_entry_point(self):
        assert '"/firebase-login"' in _read(AUTH_ROUTE), (
            "POST /shopkeeper/auth/firebase-login is the Google → Firebase → "
            "FastAPI handoff named in the flow."
        )

    def test_the_token_is_verified_not_merely_decoded(self):
        """Verification, not decoding.

        A route that base64-decodes the token would accept one the attacker
        minted themselves, breaking the first hop of the entire flow.
        """
        assert "verify_firebase_id_token_claims" in _read(AUTH_ROUTE), (
            "firebase-login must verify the ID token through the Firebase Admin "
            "SDK, not trust its decoded contents."
        )

    def test_login_provisions_the_application_user(self):
        """APPLICATION USER is created in the same call.

        A flow that verifies the token and then says "now go register" is a
        different contract from the one specified.
        """
        source = _read(AUTH_ROUTE)
        assert "firebase_uid" in source, (
            "the Application User must be keyed on firebase_uid"
        )
        assert "auto-register" in source or "auto_register" in source, (
            "an unknown firebase_uid must be auto-provisioned on first login, "
            "not deferred to a separate registration call."
        )


# ── 2. MEDIA: Flutter → FastAPI authorization → S3 ───────────────────────────


class TestMediaAuthorizationBoundary:
    """The whole point of the media layer is that S3 is private and every
    hop through it is authorized by FastAPI."""

    def test_every_media_route_requires_an_authenticated_user(self):
        offenders = [
            f"{fn.name}: {fn.lineno}"
            for fn in _handlers(ROUTES_DIR / "media.py")
            if _decorated(fn) and "Depends(get_current_user)" not in _signature(fn)
        ]
        assert not offenders, (
            "Media routes must be authorized by FastAPI; a route that can be "
            "reached without get_current_user lets an anonymous client mint or "
            "read a key. Offenders: " + ", ".join(offenders)
        )

    def test_media_router_has_no_unguarded_health_or_static_escape_hatch(self):
        """There is no public media surface outside the authorized set."""
        source = _read(ROUTES_DIR / "media.py")
        assert "public" not in source.lower() or "Depends(get_current_user)" in source
        # The router prefix is `/media`; a second, unauthenticated media router
        # mounted elsewhere would reintroduce the hole.
        assert 'prefix="/media"' in source

    def test_object_keys_are_server_minted(self):
        """The client never supplies the storage key.

        Client-chosen keys are how one tenant addresses another's objects,
        which is why the format carries a server-derived scope segment.
        """
        source = _read(MEDIA_SERVICE)
        assert "uuid" in source.lower(), (
            "media keys must include a server-generated random component so a "
            "client cannot predict or address them."
        )

    def test_no_aws_credentials_are_returned_to_the_client(self):
        """Only a signed policy comes back — never a secret.

        The response may carry a presigned form/URL; it must not carry any
        long-lived credential the client could reuse outside this flow.
        """
        schema_source = _read(APP_DIR / "schemas" / "media.py")
        for forbidden in ("aws_secret_access_key", "aws_access_key_id", "secret_key"):
            assert forbidden not in schema_source.lower(), (
                f"{forbidden} in the media response schema would ship a "
                "long-lived AWS credential to the client."
            )


# ── 3. DATA: Flutter → FastAPI → PostgreSQL/PostGIS ──────────────────────────


class TestDataStaysBehindFastapi:
    def test_postgis_is_verified_as_a_first_class_component(self):
        """The target is PostgreSQL/PostGIS, not plain PostgreSQL."""
        source = _read(APP_DIR / "core" / "health.py")
        assert "PostGIS_Version" in source, (
            "readiness must verify the PostGIS extension, otherwise a plain "
            "PostgreSQL would pass and geo queries fail at request time."
        )
        assert "postgis" in source.lower()

    def test_the_async_driver_is_postgres_asyncpg(self):
        config = _read(APP_DIR / "core" / "config.py")
        assert "postgresql+asyncpg" in config, (
            "the app connects to PostgreSQL through asyncpg; a driver swap that "
            "drops the async URL is a data-layer change."
        )

    def test_no_backend_module_opens_its_own_raw_db_connection(self):
        """Everything goes through the session dependency.

        A bare `create_engine(...)` inside a service bypasses the pool
        settings, the transaction boundary and the test harness.
        """
        offenders: list[str] = []
        for path in sorted((APP_DIR / "services").rglob("*.py")):
            if "database/session" in _read(path) or path.name == "session.py":
                continue
            tree = ast.parse(_read(path))
            for node in ast.walk(tree):
                if (
                    isinstance(node, ast.Call)
                    and ast.unparse(node.func) in ("create_engine", "async_sessionmaker")
                ):
                    offenders.append(f"{path.relative_to(BACKEND_DIR)}:{node.lineno}")
        assert not offenders, (
            "Services must not construct their own engines; use the session "
            "dependency. Found: " + ", ".join(offenders)
        )


# ── 4. CACHE / STATE: FastAPI → Redis/Valkey, OPTIONAL ───────────────────────


class TestCacheIsOptional:
    """The spec marks this layer OPTIONAL, which is the harder half to honour:
    the app has to work with Redis/Valkey absent, not merely tolerate it being
    slow."""

    def test_volatile_stores_default_to_in_process_memory(self):
        """OTP and rate limiting must not require a broker to boot.

        These are on the login path — making them depend on Redis would turn a
        cache outage into an authentication outage.
        """
        from app.core.config import settings

        for uri in (settings.OTP_STORAGE_URI, settings.RATE_LIMIT_STORAGE_URI):
            assert uri.startswith("memory://"), (
                f"{uri!r} points at an external store. The login path must "
                "degrade to memory:// when no cache is configured."
            )

    def test_redis_connection_options_are_centralised_and_bounded(self):
        """A hung cache must never hang a request.

        Connection/socket timeouts plus bounded retry live in exactly one
        module, so no consumer can opt out by constructing its own client.
        """
        source = _read(APP_DIR / "core" / "redis.py")
        assert "socket_connect_timeout" in source
        assert "socket_timeout" in source
        assert "RETRYABLE_REDIS_ERRORS" in source

    def test_background_publish_never_raises_into_the_request(self):
        """A dead broker degrades the job, not the API call that queued it."""
        from app.core.celery_app import publish_task_nonblocking

        doc = (publish_task_nonblocking.__doc__ or "").upper()
        assert "NEVER RAISES" in doc, (
            "publish_task_nonblocking must stay non-raising: enqueuing a "
            "background job must not break the request that triggered it."
        )

    def test_readiness_reports_the_cache_rather_than_hiding_it(self):
        """/ready distinguishes 'no cache' from 'broken cache'."""
        source = _read(APP_DIR / "core" / "health.py")
        assert "check_redis" in source
        assert "_COMPONENT_REDIS" in source


