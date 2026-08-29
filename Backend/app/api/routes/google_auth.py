"""Google OAuth login routes.

Mounts on the exact path derived from ``GOOGLE_CALLBACK_URL`` so the route
matches the redirect URI registered in the Google Cloud Console:

    POST {prefix}/google        → returns the Google consent URL
    GET  {prefix}/google/callback?code=...&state=... → exchanges the code,
         verifies the ID token, upserts the user, and issues JWT session tokens.

The prefix is parsed from ``GOOGLE_CALLBACK_URL`` (e.g.
``http://localhost:5000/api/auth/google/callback`` ⇒ prefix ``/api/auth``),
so this router intentionally lives outside the versioned ``/api/v1`` prefix.
"""
from urllib.parse import urlsplit

from fastapi import APIRouter, Depends, Query, Request
from fastapi.responses import RedirectResponse
from sqlalchemy.orm import Session

from app.core.config import settings
from app.database.session import get_db
from app.models.customer import Customer
from app.models.role import Role
from app.models.user import User, UserStatus
from app.services import google_oauth
from app.services.auth_service import issue_tokens

_CALLBACK_PATH = urlsplit(settings.GOOGLE_CALLBACK_URL or "").path
_PREFIX = _CALLBACK_PATH.rsplit("/google/callback", 1)[0] or "/api/auth"

router = APIRouter(prefix=_PREFIX, tags=["google-auth"])


def _default_role(db: Session) -> Role | None:
    return db.query(Role).filter(Role.name == "customer").first()


def _client_meta(request: Request) -> dict:
    return {
        "ip_address": request.client.host if request.client else None,
        "user_agent": request.headers.get("user-agent"),
    }


@router.post("/google")
async def google_login_url():
    """Return the Google consent URL for the client to open in a browser.

    A short-lived signed ``state`` token protects the callback from CSRF.
    """
    try:
        state = google_oauth.create_state_token()
        auth_url = google_oauth.build_authorization_url(state)
    except google_oauth.GoogleOAuthError as exc:
        from app.core.responses import error_response

        return error_response(
            message=str(exc), error_code="GOOGLE_OAUTH_CONFIG", status_code=500
        )
    from app.core.responses import success_response

    return success_response(data={"auth_url": auth_url, "state": state}, message="OK")


@router.get("/google/callback")
async def google_callback(
    request: Request,
    db: Session = Depends(get_db),
    code: str = Query(""),
    state: str = Query(""),
    redirect_to_frontend: int = Query(0),
):
    """Exchange the OAuth code, upsert the Google user, and issue JWTs."""
    from app.core.responses import error_response, success_response

    # ── CSRF state verification ──────────────────────────────────────────────
    if not google_oauth.validate_state_token(state):
        return error_response(
            message="Invalid or expired OAuth state", error_code="INVALID_OAUTH_STATE", status_code=400
        )
    if not code:
        return error_response(
            message="Missing Google authorization code", error_code="MISSING_OAUTH_CODE", status_code=400
        )

    # ── Exchange + verify ────────────────────────────────────────────────────
    try:
        tokens = google_oauth.exchange_code_for_tokens(code)
        profile = google_oauth.google_user_profile(tokens)
    except google_oauth.GoogleOAuthError as exc:
        return error_response(
            message=str(exc), error_code="GOOGLE_OAUTH_FAILED", status_code=401
        )

    # ── Upsert user ──────────────────────────────────────────────────────────
    user = db.query(User).filter(User.google_id == profile["google_id"]).first()
    if user is None and profile.get("email"):
        user = db.query(User).filter(User.email == profile["email"]).first()
        if user is not None and not user.google_id:
            user.google_id = profile["google_id"]  # link existing account

    if user is None:
        default_role = _default_role(db)
        user = User(
            google_id=profile["google_id"],
            email=profile.get("email"),
            name=profile.get("name"),
            avatar_url=profile.get("picture"),
            role_id=default_role.id if default_role else None,
            status=UserStatus.ACTIVE,
            is_active=True,
        )
        db.add(user)
        db.flush()

        customer = Customer(user_id=user.id)
        db.add(customer)
        db.flush()
    elif not user.is_active or user.status.value in ("SUSPENDED", "BANNED", "INACTIVE"):
        return error_response(
            message="Account is not active", error_code="ACCOUNT_NOT_ACTIVE", status_code=403
        )

    # ── Issue JWT session tokens ─────────────────────────────────────────────
    meta = _client_meta(request)
    token_data = issue_tokens(user, db, ip_address=meta["ip_address"], user_agent=meta["user_agent"])
    db.commit()

    if redirect_to_frontend:
        return _frontend_redirect(token_data)

    return success_response(data=token_data, message="Google login successful")


def _frontend_redirect(token_data: dict) -> RedirectResponse:
    """Redirect to the SPA with tokens in the URL fragment (never the query),
    guarded against open redirects by validating the frontend host."""
    from urllib.parse import urlsplit as _urlsplit, quote as _quote

    try:
        expected_host = _urlsplit(settings.FRONTEND_URL).netloc
    except Exception:  # noqa: BLE001 — config fallback
        expected_host = ""
    if not expected_host:
        from app.core.responses import JSONResponse

        return JSONResponse(content={"success": True, "data": token_data})

    fragment = "&".join(f"{k}={_quote(str(v), safe='')}" for k, v in token_data.items())
    return RedirectResponse(
        url=f"{settings.FRONTEND_URL}/auth/social#{fragment}",
        status_code=302,
    )