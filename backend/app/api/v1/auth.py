"""Authentication and the acting-admin profile."""

from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from jose import jwt
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import get_db
from app.core.responses import ok
from app.core.security import create_access_token, decode_access_token, get_current_admin, hash_password, verify_password
from app.models import AdminUser, RevokedAdminToken

router = APIRouter(tags=["auth"])

# The cookie name the frontend's apiClient looks for when no bearer token is
# present. HttpOnly so script cannot read it.
SESSION_COOKIE = "admin_session"


class LoginRequest(BaseModel):
    username: str = Field(min_length=1, max_length=64)
    password: str = Field(min_length=1, max_length=72)

class TokenLoginRequest(BaseModel):
    token: str = Field(min_length=1, max_length=4096)


def _set_session(response: Response, token: str) -> None:
    response.set_cookie(
        key=SESSION_COOKIE,
        value=token,
        httponly=True,
        samesite="lax",
        secure=settings.COOKIE_SECURE,
        max_age=60 * settings.ACCESS_TOKEN_EXPIRE_MINUTES,
        path="/",
    )
    response.headers["Cache-Control"] = "no-store"

# Keep unknown-user password checks indistinguishable from wrong-password checks.
_DUMMY_HASH = hash_password("dummy-admin-password")

@router.post("/admin/auth/login")
def login(payload: LoginRequest, response: Response, db: Session = Depends(get_db)):
    """Exchange credentials for a session.

    The token is returned in the body *and* set as an HttpOnly cookie: the
    login page reads `access_token` from the body, while subsequent requests
    can ride on the cookie alone.
    """
    admin = db.scalar(select(AdminUser).where(AdminUser.username == payload.username))
    password_ok = verify_password(payload.password, admin.hashed_password if admin else _DUMMY_HASH)
    if not password_ok or admin is None or not admin.is_active:
        # One message for both cases, so the response cannot be used to
        # enumerate valid usernames.
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid username or password",
        )
    admin.last_login = datetime.now(timezone.utc)
    db.commit()

    token = create_access_token(admin.id, {"username": admin.username})
    _set_session(response, token)
    return ok({"access_token": token, "token_type": "bearer"}, message="Signed in")


@router.post("/admin/auth/token-login")
def token_login(payload: TokenLoginRequest, response: Response, db: Session = Depends(get_db)):
    """Validate a bearer token and exchange it for a fresh, revocable session."""
    claims = decode_access_token(payload.token)
    admin = db.get(AdminUser, int(claims["sub"]))
    if admin is None or not admin.is_active or db.get(RevokedAdminToken, claims["jti"]):
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    db.add(RevokedAdminToken(jti=claims["jti"], expires_at=datetime.fromtimestamp(claims["exp"], timezone.utc)))
    token = create_access_token(admin.id, {"username": admin.username})
    db.commit()
    _set_session(response, token)
    return ok({"access_token": token, "token_type": "bearer"}, message="Signed in")

@router.post("/auth/logout")
def logout(request: Request, response: Response, db: Session = Depends(get_db)):
    header = request.headers.get("Authorization", "")
    token = header[7:] if header.lower().startswith("bearer ") else request.cookies.get(SESSION_COOKIE)
    if token:
        claims = decode_access_token(token)
        if db.get(RevokedAdminToken, claims["jti"]) is None:
            db.add(RevokedAdminToken(jti=claims["jti"], expires_at=datetime.fromtimestamp(claims["exp"], timezone.utc)))
            db.commit()
    response.delete_cookie(SESSION_COOKIE, path="/", secure=settings.COOKIE_SECURE, samesite="lax")
    response.headers["Cache-Control"] = "no-store"
    return ok(None, message="Signed out")


@router.get("/admin/me")
def me(admin: AdminUser = Depends(get_current_admin)):
    """Profile for the signed-in admin.

    `permissions` is what the frontend's PermissionGuard reads to decide which
    controls to render, so the owner is reported with the wildcard grant.
    """
    permissions = ["*"] if admin.is_owner else list(admin.permissions or [])
    return ok(
        {
            "user_id": admin.id,
            "name": admin.name or admin.username,
            "role_name": admin.role_name,
            "level": "SUPER" if admin.level == "SUPER" else "SUB",
            "permissions": permissions,
            "is_owner": bool(admin.is_owner),
        }
    )
